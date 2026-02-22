# frozen_string_literal: true

require "digest/md5"
require "net/http"
require "uri"

module Jobs
  class CreditMerchantNotify < ::Jobs::Base
    sidekiq_options retry: 5

    def execute(args)
      order_id = args[:order_id]
      return unless order_id

      order = CreditOrder.find_by(id: order_id, status: "success")
      return unless order

      stored = PluginStore.get("credit_notify", "order_#{order_id}")
      return unless stored&.dig("notify_url").present?

      app = CreditMerchantApp.find_by(client_id: order.client_id)
      return unless app

      notify_params = {
        "pid" => order.client_id,
        "trade_no" => order.id.to_s,
        "out_trade_no" => order.merchant_order_no.to_s,
        "type" => order.payment_type.to_s,
        "name" => order.order_name,
        "money" => format("%.2f", order.amount),
        "trade_status" => "TRADE_SUCCESS",
      }
      notify_params["sign"] = generate_sign(notify_params, app.client_secret)
      notify_params["sign_type"] = "MD5"

      uri = URI.parse(stored["notify_url"])
      response = Net::HTTP.post_form(uri, notify_params)

      body = response.body.to_s.strip.downcase
      unless response.is_a?(Net::HTTPSuccess) && body == "success"
        raise "Merchant notify failed: order=#{order_id} status=#{response.code} body=#{body}"
      end

      Rails.logger.info("[CreditNotify] order #{order_id} notify success")
    end

    private

    def generate_sign(params_hash, secret)
      filtered = params_hash.reject { |k, _| %w[sign sign_type].include?(k) }
      sorted_keys = filtered.keys.sort
      str = sorted_keys.map { |k| "#{k}=#{filtered[k]}" }.join("&") + secret
      Digest::MD5.hexdigest(str)
    end
  end
end
