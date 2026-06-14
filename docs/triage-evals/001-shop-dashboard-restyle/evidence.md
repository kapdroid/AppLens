# Evidence — shop.dashboard tier-3 drift

Node: shop.dashboard (module: shop)
Route: /dashboard
Visual failure: true

Failed assertions:
  - visual_match: 8.4% of pixels differ (app-bar region)

Tree diff:
on shop.dashboard, the AppBar background and title color changed; layout
unchanged.

Commits touching shop since last green:
  - abc123: restyle app bar to brand palette [lib/shop/dashboard.dart, lib/theme.dart]

Image: image_0.png (tier-3 red diff overlay; app-bar region highlighted)
