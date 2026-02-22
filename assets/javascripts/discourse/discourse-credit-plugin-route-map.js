export default function () {
  this.route("credit-wallet", { path: "/credit" });
  this.route("credit-merchant", { path: "/credit/merchant" });
  this.route("credit-product-detail", { path: "/credit/product/:id" });
  this.route("credit-my-orders", { path: "/credit/my-orders" });
  this.route("credit-admin", { path: "/credit/admin" });
}
