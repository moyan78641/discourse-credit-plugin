export default function () {
  this.route("credit-wallet", { path: "/credit" });
  this.route("credit-transfer", { path: "/credit/transfer" });
  this.route("credit-redenvelope", { path: "/credit/redenvelope" });
  this.route("credit-redenvelope-detail", { path: "/credit/redenvelope/:id" });
  this.route("credit-merchant", { path: "/credit/merchant" });
  this.route("credit-product-detail", { path: "/credit/product/:id" });
  this.route("credit-disputes", { path: "/credit/disputes" });
  this.route("credit-dashboard", { path: "/credit/dashboard" });
  this.route("credit-admin", { path: "/credit/admin" });
  this.route("credit-pay", { path: "/credit/pay" });
}
