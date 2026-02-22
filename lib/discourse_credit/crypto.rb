# frozen_string_literal: true

require "openssl"
require "securerandom"
require "base64"
require "digest"

module ::DiscourseCredit
  module Crypto
    module_function

    # Generate a random hex string of given length
    def generate_random_string(length = 32)
      SecureRandom.hex(length / 2 + 1)[0...length]
    end

    # Generate user sign key (32 chars hex)
    def generate_sign_key
      generate_random_string(32)
    end

    # Derive AES-256 key from string via SHA256
    def derive_key(key_str)
      Digest::SHA256.digest(key_str)
    end

    # AES-256-GCM encrypt
    def encrypt(key_str, plaintext)
      cipher = OpenSSL::Cipher::AES.new(256, :GCM)
      cipher.encrypt
      cipher.key = derive_key(key_str)
      iv = cipher.random_iv
      cipher.auth_data = ""
      ciphertext = cipher.update(plaintext) + cipher.final
      tag = cipher.auth_tag
      Base64.strict_encode64(iv + ciphertext + tag)
    end

    # AES-256-GCM decrypt
    def decrypt(key_str, encoded)
      data = Base64.strict_decode64(encoded)
      cipher = OpenSSL::Cipher::AES.new(256, :GCM)
      cipher.decrypt
      cipher.key = derive_key(key_str)
      # GCM iv = 12 bytes, tag = 16 bytes
      iv = data[0, 12]
      tag = data[-16, 16]
      ciphertext = data[12...-16]
      cipher.iv = iv
      cipher.auth_tag = tag
      cipher.auth_data = ""
      cipher.update(ciphertext) + cipher.final
    rescue StandardError
      nil
    end

    # Verify pay key (constant-time comparison)
    def verify_pay_key(sign_key, encrypted_pay_key, input_key)
      return false if encrypted_pay_key.blank?
      decrypted = decrypt(sign_key, encrypted_pay_key)
      return false if decrypted.nil?
      ActiveSupport::SecurityUtils.secure_compare(decrypted, input_key)
    end
  end
end
