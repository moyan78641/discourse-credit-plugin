import Route from "@ember/routing/route";

export default class CreditPaymentRoute extends Route {
  model(params) {
    return { transaction_id: params.transaction_id };
  }
}
