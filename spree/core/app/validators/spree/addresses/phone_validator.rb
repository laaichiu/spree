# This validator can be overridden to implement custom phone validation logic.
# National numbers use the address country as their parsing context; explicit
# international numbers may belong to a different country.

require 'phonelib'

module Spree
  module Addresses
    class PhoneValidator < ActiveModel::Validator
      def validate(address)
        return if !address.validates_phone? || address.phone.blank?
        return if address.phone_valid?

        address.errors.add(:phone, :invalid)
      end
    end
  end
end
