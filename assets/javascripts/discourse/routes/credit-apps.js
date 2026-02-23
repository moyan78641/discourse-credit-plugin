import Route from "@ember/routing/route";
import { service } from "@ember/service";

export default class CreditAppsRoute extends Route {
  @service router;

  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("discovery.latest");
    }
  }
}
