# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"


# This is the crucial line for your custom script:
# Option 1 (common convention for subdirectories):
# pin "custom/dashboard_quick_img_tab", to: "custom--dashboard_quick_img_tab.js"
# Option 2 (if Option 1 doesn't resolve to a 200 OK asset path):
pin "custom/dashboard_quick_img_tab", to: "custom/dashboard_quick_img_tab.js"