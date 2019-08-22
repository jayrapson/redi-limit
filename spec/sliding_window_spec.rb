RSpec.describe RediLimit::SlidingWindow do
  let(:app)            { lambda { |env| [200, {}, ['OK']] } } # I wish all apps were this simple
  let(:env)            { Rack::MockRequest.env_for('localhost', header).merge() }
  let(:rate)           { 10 }
  let(:window)         { 60 }
  let(:header)         { { header_group => 'bearer auth_token' } }
  let(:header_group)   { 'HTTP_AUTHORIZATION' }
  let(:sliding_window) { RediLimit::SlidingWindow.new(app, rate, window, header_group) }

  subject { sliding_window }

  describe :initialize do
    context 'when passed valid parameters' do
      it 'has window set correctly' do
        expect(subject.instance_variable_get(:@window)).to eq(window)
      end

      it 'has rate set correctly' do
        expect(subject.instance_variable_get(:@rate)).to eq(rate)
      end

      it 'has header_group set correctly' do
        expect(subject.instance_variable_get(:@header_group)).to eq(header_group)
      end
    end

    context 'when passed an invalid' do
      context :rate do
        let(:rate) { 0 }
        it 'will raise a contract error' do
          expect { subject }.to raise_error(ParamContractError)
        end

        context 'with an invalid type' do
          let(:rate) { '10' }
          it 'will raise a contract error' do
            expect { subject }.to raise_error(ParamContractError)
          end
        end
      end

      context :window do
        context 'with a value which is not positive' do
          let(:window) { 0 }
          it 'will raise a contract error' do
            expect { subject }.to raise_error(ParamContractError)
          end
        end

        context 'with an invalid type' do
          let(:window) { '10' }
          it 'will raise a contract error' do
            expect { subject }.to raise_error(ParamContractError)
          end
        end
      end

      context :header_group do
        context 'with an invalid type' do
          let(:header_group) { 10 }
          it 'will raise a contract error' do
            expect { subject }.to raise_error(ParamContractError)
          end
        end
      end
    end
  end

  describe :skip? do
    subject { sliding_window.skip?(env) }

    context 'when the relevant key is present' do
      it { should be false }
    end

    context 'when the relevant key is not present' do
      let(:env) { {} }
      it { should be true }
    end
  end

  describe :limit do
    subject { sliding_window.limit(env) }

    context 'when they have not reached the number of requests to rate limit' do
      before do
        allow(sliding_window).to receive(:run_script).and_return(nil)
      end

      it 'will return a successful response' do
        (code, _, response) = subject
        expect(code).to eq(200)
        expect(response).to eq(['OK'])
      end
    end

    context 'when they have reached the number of requests to rate limit' do
      context 'but the request is outside the window' do
        before do
          allow(sliding_window).to receive(:run_script).and_return(-1)
        end

        it 'will return a successful response' do
          (code, _, response) = subject
          expect(code).to eq(200)
          expect(response).to eq(['OK'])
        end
      end

      context 'and they are on the edge of the window' do
        before do
          allow(sliding_window).to receive(:run_script).and_return(0)
        end

        it 'will return a successful response' do
          (code, _, response) = subject
          expect(code).to eq(200)
          expect(response).to eq(['OK'])
        end
      end

      context 'and they should be restricted' do
        before do
          allow(sliding_window).to receive(:run_script).and_return(1)
        end

        it 'will return a rate limited response' do
          (code, _, response) = subject
          expect(code).to eq(429)
          expect(response[0]).to match(/Rate limit exceeded, try again in 1 seconds/)
        end
      end
    end
  end

  # DANGER DANGER! HIGH VOLTAGE!
  # This portion of the spec requires redis connectivity on the localhost. This is less than ideal
  # and would normally be mocked or stubbed, but given the implementation with a remotely executed
  # lua script, redis-mock doesn't support this and mocking the call is next to useless in general.
  # Due to the fact this script has low cyclomatic complexity I've settled with black box testing for
  # this task, but to have a full view of coverage etc. you'd generally implement checks on the lua
  # script itself via the busted testing framework (though this doesn't play nicely with redis lua)
  describe :run_script do
    let!(:redis)     { Redis.new(host: :localhost) } # (danger danger)
    let(:identifier) { 'identifier' }

    before do
      redis.flushall # clear all of the existing keys
    end

    context 'when they have not reached the number of requests to rate limit' do
      let(:rate) { 3 }

      context 'with a single request' do
        before do
          sliding_window.run_script(identifier, window, rate, Time.now.to_i)
        end

        it 'will add the request to redis for this identifier' do
          expect(redis.llen(identifier)).to eq(1)
        end

        it 'will not add a key to block further requests' do
          expect(redis.get("#{identifier}_limit")).to eq(nil)
        end

        it 'will return an empty response' do
          expect(sliding_window.run_script(identifier, window, rate, Time.now.to_i)).to eq(nil)
        end
      end

      context 'with multiple requests' do
        let(:create_amount) { rate - 1 }

        before do
          create_amount.times do
            sliding_window.run_script(identifier, window, rate, Time.now.to_i)
          end
        end
        
        it 'will add the request to redis for this identifier' do
          expect(redis.llen(identifier)).to eq(create_amount)
        end

        it 'will not add a key to block further requests' do
          expect(redis.exists("#{identifier}_limit")).to be false
        end

        it 'will return an empty response' do
          expect(sliding_window.run_script(identifier, window, rate, Time.now.to_i)).to eq(nil)
        end
      end
    end

    context 'when they have reached the number of requests to rate limit' do
      let(:rate)           { 3 }
      let(:create_amount)  { rate + 1 }

      context 'but the request is outside the window' do
        before do
          # add a data structure to test this, as the only concept of time the script has is what is
          # actively passed in.
          create_amount.times do
            redis.lpush(identifier, 1000)
          end
          # run the script to ensure any potential blocks will be applied
          sliding_window.run_script(identifier, window, rate, Time.now.to_i)
        end
        
        it 'will trim the requests for this identifier' do
          expect(redis.llen(identifier)).to eq(rate)
        end

        it 'will not add a key to block further requests' do
          expect(redis.exists("#{identifier}_limit")).to be false
        end

        it 'will return an empty response' do
          expect(sliding_window.run_script(identifier, window, rate, Time.now.to_i)).to eq(nil)
        end
      end

      context 'and they should be restricted' do
        before do
          create_amount.times do
            sliding_window.run_script(identifier, window, rate, Time.now.to_i)
          end
        end
        
        it 'will not add the request to redis for this identifier' do
          expect(redis.llen(identifier)).to eq(rate)
        end

        it 'will add a key to block further requests' do
          expect(redis.exists("#{identifier}_limit")).to be true
        end

        it 'will stop blocking requests at the end of the window timeframe' do
          expect(redis.ttl("#{identifier}_limit")).to be_within(1).of(window)
        end

        it 'will return the number of seconds until the block is removed' do
          expect(sliding_window.run_script(identifier, window, rate, Time.now.to_i)).to be_within(1).of(window)
        end
      end
    end

    context 'when the script no longer exists' do
      it 'loads the script back into redis and executes' do
        # run once to load script
        sliding_window.run_script(identifier, window, rate, Time.now.to_i)

        # remove the loaded script from redis
        redis.script(:flush) 

        # set an expectation via a mock, but we still need to actually call the original method to
        # avoid raising an exception
        expect(sliding_window).to receive(:load_script!).and_call_original
        
        # trigger the actual call itself
        sliding_window.run_script(identifier, window, rate, Time.now.to_i)
      end
    end
  end
end