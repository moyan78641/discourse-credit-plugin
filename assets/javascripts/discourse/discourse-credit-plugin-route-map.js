export default function () {
  this.route("credit-wallet", { path: "/credit" });
  this.route("credit-merchant", { path: "/credit/merchant" });
  this.route("credit-product-detail", { path: "/credit/product/:id" });
  this.route("credit-admin", { path: "/credit/admin" });
}
