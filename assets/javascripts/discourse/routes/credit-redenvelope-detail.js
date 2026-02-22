import DiscourseRoute from "discourse/routes/discourse";
import { service } from "@ember/service";

export default class CreditRedenvelopeDetailRoute extends DiscourseRoute {
  @service router;

  beforeModel() {
    if (!this.currentUser) {
      this.router.replaceWith("discovery.latest");
    }
  }
}
