# stranger_app

A small demo Flutter app — a five-screen shopping flow (home → catalog →
product → cart → order confirmation, plus a settings screen) with one long
scrollable list (the 60-item catalog).

It exists as **AppLens's permanent zero-special-access proof**: the
`examples/stranger_app` integration must stay green using only the public
interface and the README. The day it needs special access, the product has
regressed into an internal tool — so fix the product, not this app (see
[`../../CLAUDE.md`](../../CLAUDE.md), the stranger-app rule).

Widgets carry stable `Key`s (`btn_place_order`, `list_cart_items`, `lbl_total`,
`product_<id>`, …) so they can serve as graph anchors once `applens init` wires
this app up in Session 5.

## Attribution

This is an **original** app authored for the AppLens project, licensed
Apache-2.0 with the rest of the repository. The build plan suggests *vendoring* a
third-party open-source demo; an original app was chosen instead for a clean,
unambiguous license story while still satisfying the stranger-app contract. If a
real-world third-party app is later vendored to harden that proof, its upstream
attribution belongs here.

## Run

```bash
flutter test            # headless widget flow (the Session 0 build proof)
flutter run             # on an emulator/device
```
