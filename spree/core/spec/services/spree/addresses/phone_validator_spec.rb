require 'spec_helper'

describe Spree::Addresses::PhoneValidator do
  subject { described_class.new }

  shared_examples 'does not add a phone error' do
    it 'does not add an error' do
      subject.validate(address)
      expect(address.errors[:phone]).to be_empty
    end
  end

  before { stub_store_preferences(address_requires_phone: true, address_validates_phone: false) }

  describe '#validate' do
    context 'when no phone is provided' do
      let(:address) { create(:address, phone: nil) }

      before do
        stub_store_preferences(address_requires_phone: false, address_validates_phone: true)
      end

      it_behaves_like 'does not add a phone error'
    end

    context 'when a national number has no country context' do
      let(:address) { build_stubbed(:address, phone: '2025550123', country: nil) }

      it 'adds an error' do
        subject.validate(address)
        expect(address.errors[:phone]).to include('is invalid')
      end
    end

    context 'when an explicit international number has no address country' do
      let(:address) { build_stubbed(:address, phone: '+48587530227', country: nil) }

      it_behaves_like 'does not add a phone error'
    end

    context 'when an optional phone is invalid' do
      let(:address) { build_stubbed(:address, phone: '1234567890') }

      before do
        stub_store_preferences(address_requires_phone: false, address_validates_phone: true)
      end

      it 'adds an error' do
        subject.validate(address)
        expect(address.errors[:phone]).to include('is invalid')
      end
    end

    context 'when phone is required but a quick-checkout address contains an invalid number' do
      let(:address) { build_stubbed(:address, phone: '1234567890', quick_checkout: true) }

      before do
        allow(address).to receive(:store_preference).with(:address_requires_phone, false).and_return(true)
        allow(address).to receive(:store_preference).with(:address_validates_phone, false).and_return(false)
      end

      it 'validates the supplied number while deferring presence' do
        subject.validate(address)
        expect(address.errors[:phone]).to include('is invalid')
      end
    end

    context 'when an international number contains an extension' do
      let(:address) { build_stubbed(:address, phone: '+1 202-555-0123;ext=44') }

      it 'adds an error rather than silently dropping the extension' do
        subject.validate(address)
        expect(address.errors[:phone]).to include('is invalid')
      end
    end

    context 'when phone is provided' do
      context 'and country is US' do
        context 'and phone is valid' do
          let(:address) { create(:address, phone: phone) }

          context 'without prefix' do
            let(:phone) { '2025550123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has prefix with plus sign' do
            let(:phone) { '+12025550123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has prefix without plus sign' do
            let(:phone) { '12025550123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashes' do
            let(:phone) { '202-555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashes and prefix' do
            let(:phone) { '+1202-555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashes and prefix without plus sign' do
            let(:phone) { '1202-555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashes and prefix after dash' do
            let(:phone) { '1-202-555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashed and parenthesized' do
            let(:phone) { '(202) 555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashed and parenthesized and prefix' do
            let(:phone) { '+1(202) 555-0123' }

            it_behaves_like 'does not add a phone error'
          end

          context 'and has dashed and parenthesized and prefix without plus sign' do
            let(:phone) { '1(202) 555-0123' }

            it_behaves_like 'does not add a phone error'
          end
        end

        context 'and phone is invalid' do
          let(:address) { build_stubbed(:address, phone: phone) }

          context 'and phone is an explicit international number from another country' do
            let(:phone) { '+48587530227' } # Poland

            it_behaves_like 'does not add a phone error'
          end

          context 'because not matching US area code' do
            let(:phone) { '1234567890' }

            it 'adds an error' do
              subject.validate(address)
              expect(address.errors[:phone]).to include('is invalid')
            end
          end
        end
      end

      context 'when the international phone country differs from the address country' do
        let(:phone) { '+1(202) 555-0123' } # US
        let(:country) { create(:country, iso: 'PL') }
        let(:address) { build_stubbed(:address, phone: phone, country: country) }

        it_behaves_like 'does not add a phone error'
      end
    end
  end
end
