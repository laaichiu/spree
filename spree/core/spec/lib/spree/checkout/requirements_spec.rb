require 'spec_helper'

RSpec.describe Spree::Checkout::Requirements do
  after { Spree::Checkout::Registry.reset! }

  let(:store) { create(:store) }
  let(:order) { create(:order, store: store) }

  subject { described_class.new(order).call }

  describe 'line items requirement' do
    it 'requires line_items when cart is empty' do
      expect(subject).to include(
        a_hash_including(step: 'cart', field: 'line_items')
      )
    end

    it 'does not require line_items when cart has items' do
      create(:line_item, order: order)
      order.reload

      expect(subject).not_to include(
        a_hash_including(step: 'cart', field: 'line_items')
      )
    end
  end

  describe 'email requirement' do
    it 'requires email when not set' do
      order.update_column(:email, nil)
      order.reload

      expect(subject).to include(
        a_hash_including(step: 'address', field: 'email')
      )
    end

    it 'does not require email when set' do
      order.update_column(:email, 'test@example.com')
      order.reload

      expect(subject).not_to include(
        a_hash_including(step: 'address', field: 'email')
      )
    end
  end

  describe 'ship_address requirement' do
    it 'requires ship_address for physical orders without address' do
      allow(order).to receive(:shipping_address_required?).and_return(true)
      order.ship_address = nil

      expect(subject).to include(
        a_hash_including(step: 'address', field: 'ship_address')
      )
    end

    it 'does not require ship_address for digital orders' do
      allow(order).to receive(:shipping_address_required?).and_return(false)

      expect(subject).not_to include(
        a_hash_including(step: 'address', field: 'ship_address')
      )
    end
  end

  describe 'phone policy requirement' do
    let(:phone) { '1234567890' }
    let(:address) do
      Spree::Current.set(store: store) { create(:address, phone: phone) }
    end
    let(:ship_address) { address }
    let(:bill_address) { address }
    let(:order) do
      create(:order, store: store).tap do |record|
        record.update_column(:ship_address_id, ship_address.id)
        record.update_column(:bill_address_id, bill_address.id)
      end
    end
    let(:requirements) do
      Spree::Current.set(store: store) { described_class.new(order.reload).call }
    end
    let(:completion_requirements) do
      Spree::Current.set(store: store) { described_class.new(order.reload).call(completion: true) }
    end

    context 'when a nonblank phone is invalid under the current policy' do
      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_validates_phone: false)
          address
          order
          store.update!(preferred_address_validates_phone: true)
        end
      end

      it 'reports the invalid phone as a checkout requirement' do
        expect(requirements).to include(
          a_hash_including(step: 'address', field: 'phone', code: 'phone_invalid', message: 'Phone is invalid')
        )
      end

      it 'uses the cart store when no request store is set' do
        result = Spree::Current.set(store: nil) { described_class.new(order.reload).call(completion: true) }

        expect(result).to include(a_hash_including(field: 'phone', code: 'phone_invalid'))
      end

      it 'does not use another store from the request context' do
        other_store = create(:store)
        result = Spree::Current.set(store: other_store) { described_class.new(order.reload).call }

        expect(result).to include(a_hash_including(field: 'phone', code: 'phone_invalid'))
      end

      it 'does not normalize unrelated address fields while reading requirements' do
        cart = order.reload
        checkout_address = cart.ship_address
        checkout_address.update_columns(country_code: 'GB', state_code: 'CA')

        expect { Spree::Current.set(store: store) { described_class.new(cart).call } }.not_to change(checkout_address, :state_code)
        expect { Spree::Current.set(store: store) { checkout_address.valid? } }.to change(checkout_address, :state_code).from('CA').to(nil)
      end
    end

    context 'when the built-in phone validator is removed' do
      around do |example|
        original_validators = Spree.validators.addresses.dup
        example.run
      ensure
        Spree.validators.addresses.replace(original_validators)
      end

      it 'does not reintroduce the removed rule at checkout' do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_validates_phone: false)
          address
          order
          store.update!(preferred_address_validates_phone: true)
        end
        Spree.validators.addresses.unregister(Spree::Addresses::PhoneValidator)

        expect(requirements).not_to include(a_hash_including(field: 'phone'))
      end
    end

    context 'when a custom phone validator is registered' do
      let(:phone) { '2025550123' }

      around do |example|
        original_validators = Spree.validators.addresses.dup
        example.run
      ensure
        Spree.validators.addresses.replace(original_validators)
      end

      it 'uses the registered rule for a saved address' do
        Spree::Current.set(store: store) do
          address
          order
          store.update!(preferred_address_validates_phone: true)
        end
        stub_const('SpecCheckoutPhoneValidator', Class.new(ActiveModel::Validator) do
          def validate(record)
            record.errors.add(:phone, :invalid)
          end
        end)
        Spree.validators.addresses.register(SpecCheckoutPhoneValidator)

        expect(requirements).to include(a_hash_including(field: 'phone', code: 'phone_invalid'))
      end
    end

    context 'when the current policy requires a missing phone' do
      let(:phone) { nil }

      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_requires_phone: false)
          address
          order
          store.update!(preferred_address_requires_phone: true)
        end
      end

      it 'reports the missing phone as a checkout requirement' do
        expect(requirements).to include(
          a_hash_including(step: 'address', field: 'phone', code: 'phone_required', message: "Phone can't be blank")
        )
      end
    end

    context 'when an explicit international phone is valid for a different country' do
      let(:phone) { '+48 58 753 02 27' }

      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_validates_phone: false)
          address
          order
          store.update!(preferred_address_validates_phone: true)
        end
      end

      it 'does not add a phone requirement' do
        expect(requirements).not_to include(a_hash_including(field: 'phone'))
      end
    end

    context 'when a quick-checkout address defers phone requiredness' do
      let(:phone) { nil }
      let(:address) do
        Spree::Current.set(store: store) do
          create(:address, phone: phone, quick_checkout: true)
        end
      end

      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_requires_phone: false)
          address
          order
          store.update!(preferred_address_requires_phone: true)
        end
      end

      it 'defers the missing phone requirement on ordinary cart reads' do
        expect(requirements).not_to include(a_hash_including(field: 'phone'))
      end

      it 'enforces the store phone requirement at final completion' do
        expect(completion_requirements).to include(
          a_hash_including(step: 'address', field: 'phone', code: 'phone_required')
        )
      end
    end

    context 'when only a different billing address has an invalid phone' do
      let(:ship_address) { valid_address }
      let(:bill_address) { address }
      let(:valid_address) do
        Spree::Current.set(store: store) { create(:address, phone: '2025550123') }
      end

      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_validates_phone: false)
          address
          valid_address
          order
          store.update!(preferred_address_validates_phone: true)
        end
      end

      it 'reports the billing phone as a checkout requirement' do
        expect(requirements).to include(
          a_hash_including(step: 'address', field: 'phone', code: 'phone_invalid', address_type: 'billing')
        )
      end
    end

    context 'when both addresses have invalid phones' do
      let(:bill_address) do
        Spree::Current.set(store: store) { create(:address, phone: '1234567890') }
      end

      before do
        Spree::Current.set(store: store) do
          store.update!(preferred_address_validates_phone: false)
          address
          bill_address
          order
          store.update!(preferred_address_validates_phone: true)
        end
      end

      it 'identifies each address in the requirements' do
        phone_requirements = requirements.select { |requirement| requirement[:field] == 'phone' }

        expect(phone_requirements).to contain_exactly(
          a_hash_including(code: 'phone_invalid', address_type: 'shipping'),
          a_hash_including(code: 'phone_invalid', address_type: 'billing')
        )
      end
    end
  end

  describe 'shipping_method requirement' do
    let(:order) { create(:order_with_line_items, store: store) }

    it 'requires shipping_method when delivery step exists and no shipments have methods' do
      allow(order).to receive(:has_checkout_step?).with('delivery').and_return(true)
      allow(order).to receive(:has_checkout_step?).with('payment').and_return(true)
      allow(order).to receive(:delivery_step_required?).and_return(true)
      order.shipments.destroy_all

      expect(subject).to include(
        a_hash_including(step: 'delivery', field: 'delivery_method')
      )
    end

    it 'reports part of a line in no fulfillment before completion, so the buyer can change it' do
      line_item = order.line_items.first
      line_item.update_column(:quantity, line_item.quantity + 1)

      expect(described_class.new(order.reload).call).to include(
        a_hash_including(step: 'delivery', code: 'delivery_unavailable')
      )
    end

    it 'checks the lines short of a fulfillment together, so more of them cost no more queries' do
      cart_with_short_lines = lambda do |count|
        create(:order_with_line_items, store: store, line_items_count: count).tap do |cart|
          cart.line_items.each { |line_item| line_item.update_column(:quantity, line_item.quantity + 1) }
        end.reload
      end
      # Inside the store a request runs in, as without one every stock check looks the default store up.
      query_count = lambda do |cart|
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) || payload[:cached] }
        Spree::Current.set(store: store) do
          ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { described_class.new(cart).call }
        end
        count
      end

      two, three = cart_with_short_lines.call(2), cart_with_short_lines.call(3)

      expect(query_count.call(three)).to eq(query_count.call(two))
    end

    it 'completes once every unit of every line is in a fulfillment' do
      expect(described_class.new(order).call(completion: true))
        .not_to include(a_hash_including(code: 'delivery_unavailable'))
    end

    it 'leaves a line short of stock to the stock check' do
      line_item = order.line_items.first
      line_item.update_column(:quantity, line_item.quantity + 1)
      line_item.variant.stock_levels.update_all(count_on_hand: 0, backorderable: false)

      codes = described_class.new(order.reload).call(completion: true).map { |requirement| requirement[:code] }
      expect(codes).to include('out_of_stock')
      expect(codes).not_to include('delivery_unavailable')
    end

    it 'says nothing of delivery before any can be proposed' do
      order.fulfillments.destroy_all

      expect(described_class.new(order.reload).call(completion: true))
        .not_to include(a_hash_including(code: 'delivery_unavailable'))
    end

    it 'does not require shipping_method when no delivery step' do
      allow(order).to receive(:has_checkout_step?).with('delivery').and_return(false)
      allow(order).to receive(:has_checkout_step?).with('payment').and_return(true)

      expect(subject).not_to include(
        a_hash_including(step: 'delivery', field: 'delivery_method')
      )
    end
  end

  describe 'payment requirement' do
    let(:order) { create(:order_with_line_items, store: store) }

    it 'requires payment when payment is required and no valid payments' do
      allow(order).to receive(:has_checkout_step?).with('delivery').and_return(true)
      allow(order).to receive(:has_checkout_step?).with('payment').and_return(true)
      allow(order).to receive(:payment_required?).and_return(true)

      expect(subject).to include(
        a_hash_including(step: 'payment', field: 'payment')
      )
    end

    it 'does not require payment for free orders' do
      allow(order).to receive(:has_checkout_step?).with('delivery').and_return(true)
      allow(order).to receive(:has_checkout_step?).with('payment').and_return(true)
      allow(order).to receive(:payment_required?).and_return(false)

      expect(subject).not_to include(
        a_hash_including(step: 'payment', field: 'payment')
      )
    end

    it 'keeps asking for payment while one only covers part of the total' do
      create(:payment, amount: order.total - 1, order: order)
      order.reload

      expect(subject).to include(
        a_hash_including(step: 'payment', field: 'payment')
      )
    end

    it 'stops asking once payments cover the total' do
      create(:payment, amount: order.total, order: order)
      order.reload

      expect(subject).not_to include(
        a_hash_including(step: 'payment', field: 'payment')
      )
    end

    it 'ignores a failed payment when measuring coverage' do
      create(:payment, amount: order.total, order: order, status: 'failed')
      order.reload

      expect(subject).to include(
        a_hash_including(step: 'payment', field: 'payment')
      )
    end
  end

  describe 'po_number requirement' do
    let(:customer) { create(:user) }
    let(:company) { create(:company, store: store, po_number_required: true) }

    before do
      create(:company_membership, company: company, customer: customer)
      order.update_columns(customer_id: customer.id, company_id: company.id)
      order.reload
    end

    it 'asks for the reference when the buyer\'s company demands one' do
      expect(subject).to include(
        a_hash_including(step: 'address', field: 'po_number', code: 'po_number_required')
      )
    end

    it 'stops asking once the buyer supplies it' do
      order.update!(po_number: 'PO-4471')

      expect(subject).not_to include(a_hash_including(field: 'po_number'))
    end

    it 'does not ask when the company does not demand one' do
      company.update!(po_number_required: false)
      order.reload

      expect(subject).not_to include(a_hash_including(field: 'po_number'))
    end

    # Payment is dropped from the steps of a cart that owes nothing, so a
    # requirement naming that step would be one the buyer can never reach.
    it 'reports against a step that survives on a cart owing nothing' do
      cart = create(:cart, store: store, customer: customer)
      cart.update_column(:company_id, company.id)
      allow(cart).to receive(:payment_required?).and_return(false)

      requirements = described_class.new(cart).call
      po_requirement = requirements.find { |requirement| requirement[:field] == 'po_number' }

      expect(po_requirement).to be_present
      expect(cart.checkout_steps).to include(po_requirement[:step])
    end

    it 'does not ask of staff keying the order in' do
      order.update_columns(created_by_id: create(:admin_user).id)
      order.reload

      expect(subject).not_to include(a_hash_including(field: 'po_number'))
    end
  end

  describe 'assortment requirement' do
    let(:customer) { create(:user) }
    let(:company) { create(:company, store: store) }
    let(:catalog) { create(:catalog, store: store) }
    let(:hidden) { create(:product, store: store, name: 'Gravel Bike') }
    let(:cart) { create(:cart, store: store, customer: customer) }

    before do
      create(:catalog_product, catalog: catalog, product: create(:product, store: store))
      create(:catalog_assignment, catalog: catalog, assignable: company)
      create(:company_membership, company: company, customer: customer)
    end

    # A guest cart claimed after sign-in carries lines no add ever checked
    # against this buyer's catalogs.
    it "refuses a line outside the buyer's catalogs at completion" do
      create(:line_item, cart: cart, order: nil, variant: hidden.default_variant)

      expect(described_class.new(cart.reload).call(completion: true)).to include(
        a_hash_including(step: 'cart', field: 'line_items', code: 'not_orderable', message: include('Gravel Bike'))
      )
    end

    it 'accepts a line inside them' do
      create(:catalog_product, catalog: catalog, product: hidden)
      create(:line_item, cart: cart, order: nil, variant: hidden.default_variant)

      expect(described_class.new(cart.reload).call(completion: true)).not_to include(a_hash_including(code: 'not_orderable'))
    end

    it 'reports a discontinued line once' do
      hidden.update_column(:discontinue_on, 1.day.ago)
      create(:line_item, cart: cart, order: nil, variant: hidden.default_variant)

      codes = described_class.new(cart.reload).call(completion: true).map { |requirement| requirement[:code] }

      expect(codes).to include('discontinued')
      expect(codes).not_to include('not_orderable')
    end

    it "does not hold back staff's draft order" do
      order.update_columns(customer_id: customer.id)
      create(:line_item, order: order, variant: hidden.default_variant)

      expect(described_class.new(order.reload).call(completion: true)).not_to include(a_hash_including(code: 'not_orderable'))
    end
  end

  describe 'fully ready order' do
    let(:order) { create(:order_with_line_items, store: store, state: 'payment') }

    before do
      create(:payment, amount: order.total, order: order)
      order.reload
    end

    it 'returns empty array' do
      expect(subject).to eq([])
    end
  end

  describe 'custom registered step' do
    it 'includes requirements from unsatisfied applicable steps' do
      Spree::Checkout::Registry.register_step(
        name: :custom,
        satisfied: ->(_order) { false },
        requirements: ->(_order) { [{ step: 'custom', field: 'custom_field', message: 'Custom required' }] },
        applicable: ->(_order) { true }
      )

      expect(subject).to include(
        a_hash_including(step: 'custom', field: 'custom_field', message: 'Custom required')
      )
    end

    it 'excludes requirements from satisfied steps' do
      Spree::Checkout::Registry.register_step(
        name: :custom,
        satisfied: ->(_order) { true },
        requirements: ->(_order) { [{ step: 'custom', field: 'custom_field', message: 'Custom required' }] }
      )

      expect(subject).not_to include(
        a_hash_including(step: 'custom', field: 'custom_field')
      )
    end

    it 'excludes requirements from non-applicable steps' do
      Spree::Checkout::Registry.register_step(
        name: :custom,
        satisfied: ->(_order) { false },
        requirements: ->(_order) { [{ step: 'custom', field: 'custom_field', message: 'Custom required' }] },
        applicable: ->(_order) { false }
      )

      expect(subject).not_to include(
        a_hash_including(step: 'custom', field: 'custom_field')
      )
    end
  end

  describe 'custom additional requirement' do
    it 'includes unsatisfied applicable requirements' do
      Spree::Checkout::Registry.add_requirement(
        step: :payment,
        field: :po_number,
        message: 'PO number is required for B2B',
        satisfied: ->(_order) { false },
        applicable: ->(_order) { true }
      )

      expect(subject).to include(
        a_hash_including(step: 'payment', field: 'po_number', message: 'PO number is required for B2B')
      )
    end

    it 'excludes satisfied requirements' do
      Spree::Checkout::Registry.add_requirement(
        step: :payment,
        field: :po_number,
        message: 'PO number is required for B2B',
        satisfied: ->(_order) { true }
      )

      expect(subject).not_to include(
        a_hash_including(step: 'payment', field: 'po_number')
      )
    end

    it 'excludes non-applicable requirements' do
      Spree::Checkout::Registry.add_requirement(
        step: :payment,
        field: :po_number,
        message: 'PO number is required for B2B',
        satisfied: ->(_order) { false },
        applicable: ->(_order) { false }
      )

      expect(subject).not_to include(
        a_hash_including(step: 'payment', field: 'po_number')
      )
    end
  end

  describe '#met?' do
    it 'returns false when requirements exist' do
      expect(described_class.new(order).met?).to be false
    end

    it 'returns true when all requirements are met' do
      order = create(:order_with_line_items, store: store, state: 'payment')
      create(:payment, amount: order.total, order: order)
      order.reload
      expect(described_class.new(order).met?).to be true
    end
  end
end
