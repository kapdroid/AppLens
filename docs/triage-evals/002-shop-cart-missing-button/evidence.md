# Evidence — shop.cart tier-1 failure

Node: shop.cart (module: shop)
Route: /cart
Visual failure: false

Failed assertions:
  - widget_exists: key "btn_place_order" not present

Tree diff:
on shop.cart, the place-order button is absent from the tree; the cart list
renders normally.

Commits touching shop since last green:
  (none — nothing recent explains this change)
