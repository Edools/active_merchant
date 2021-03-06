require File.dirname(__FILE__) + '/helpers_pagarme.rb'
require File.dirname(__FILE__) + '/response_pagarme.rb'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module PagarmeRecurringApi #:nodoc:
      include ActiveMerchant::Billing::PagarmeRecurringApi::HelpersPagarme
      include ActiveMerchant::Billing::PagarmeRecurringApi::ResponsePagarme

      def recurring(amount, credit_card, options = {})
        begin
          requires!(options, :payment_method)

          params = {
            payment_method: options[:payment_method],
            customer: ensure_customer_created(options),
            plan_id: options["subscription"]["plan_code"],
          }

          if options[:payment_method] == 'credit_card'
            if options[:card_id].present?
              params[:card_id] = options[:card_id]
            elsif options[:card_hash].present?
              params[:card_hash] = options[:card_hash]
            else
              add_credit_card(params, credit_card)
            end
          end

          # params[:postback_url] = "https://services.edools.com/nasp/pagarme/To9v28dQqJ6tpcc65gHr1rIHQAzxbN8RVwUS1nH4/#{options[:transaction_id]}"

          response            = commit(:post, 'subscriptions', params)
          card                = response.params["card"]
          response_options    = {
            authorization:       response.params['id'],
            subscription_action: SUBSCRIPTION_STATUS_MAP[response.params['status']],
            test:                response.test?,
            card:                card,
            invoice_id:          response.params['id'],
            next_charge_at:      response.params['current_period_end']
          }

          current_transaction = response.params['current_transaction']

          if current_transaction.present?
            response_options[:payment_action] = PAYMENT_STATUS_MAP[current_transaction["status"]]
            response_options[:boleto_url]     = current_transaction['boleto_url']
          end

          Response.new(response.success?, response.message,
            subscription_to_response(response.params), response_options)
        rescue => error
          Response.new(false, error.message, {}, test: test?)
        end
      end

      def update(invoice_id, options)
        requires!(options, :payment_method)

        acceptable_options = %i(payment_method plan_id card_id card_hash card_number card_holder_name)
        params = options.select { |k,v| acceptable_options.include?(k) && v.present? }

        if options[:card_expiration_date].present? && expiration_date(options[:card_expiration_date])
          params[:card_expiration_date] = options[:card_expiration_date]
        end

        commit(:put, "subscriptions/#{invoice_id}", params)
      end

      def cancel_recurring(invoice_id)
        params = {}

        commit(:post, "subscriptions/#{invoice_id}/cancel", params)
      end

      def invoice(invoice_id)
        response = commit(:get, "transactions/#{invoice_id}", nil)

        Response.new(true, nil, {invoice: invoice_to_response(response.params)})
      end

      def last_payment_from_invoice(invoice_id)
        response     = PagarMe::Subscription.find_by_id(invoice_id)
        last_payment = response.transactions.last
        last_code    = last_payment.status
        options      = {
          test: test?,
          payment_action: PAYMENT_STATUS_MAP[last_code]
        }

        Response.new(response[:success], nil, payment_to_response(last_payment), options)
      end

      def invoices(subscription_id)
        invoices      = []
        subscription  = PagarMe::Subscription.find_by_id(subscription_id)
        plan          = subscription.plan
        invoice_start = Date.parse(subscription.date_created) + plan.trial_days
        invoice_end   = invoice_start + plan.days - 1.day

        while invoice_start < Time.now
          invoices << {
            id: subscription_id,
            created_at: invoice_start,
            next_charge_at: invoice_end,
            amount: plan.amount
          }

          invoice_start = invoice_end
          invoice_end += plan.days
        end

        Response.new(true, nil, { invoices: invoices })
      end

      def payments(invoice)
        payments = []
        response = service_pagarme.payments_from_invoice(invoice.gateway_reference)

        payments = response.select do |payment|
          if payment['payment_method'] == 'boleto'
            boleto_expiration_date = DateTime.parse(payment["boleto_expiration_date"])

            belongs_same_invoice_month = invoice.next_charge_at.month - boleto_expiration_date.month == 1
            belongs_same_invoice_year  = invoice.next_charge_at.year - boleto_expiration_date.year == 1

            belongs_same_invoice_month || belongs_same_invoice_year
          else
            created_at = payment['date_created']

            created_at > invoice.created_at && created_at < invoice.next_charge_at
          end
        end

        payments = payments.sort_by { |payment| payment['date_created'] }

        Response.new(true, nil, { payments: payments_to_response(payments) })
      end

      def payment(payment_id)
        response = service_pagarme.payment(payment_id)

        Response.new(true, nil, { payment: payment_to_response(response) })
      end

      def subscription_details(subscription_code)
        response     = PagarMe::Subscription.find_by_id(subscription_code)
        subscription = subscription_to_response(response)

        Response.new(true, nil, subscription, test: test?,
          subscription_action: subscription[:action],
          next_charge_at: subscription[:current_period_end])
      end

      private

      def expiration_date(date)
        if /((1[0-2]|0[1-9])([0-9]){2})/ =~ date
          date
        else
          raise "Data de expiração do cartão com formato inválido"
        end
      end

      def ensure_customer_created(options)
        customer = create_customer(options[:customer], options[:address])

        customer['addresses'] ? customer_response(customer) : customer
      end

      def create_customer(customer, address)
        params = customer_params(customer, address)

        PagarMe::Customer.new(params).create.to_hash
      end
    end
  end
end
