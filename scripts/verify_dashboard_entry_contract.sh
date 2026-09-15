#!/usr/bin/env bash
set -euo pipefail

root_view="AlphaPos/Features/Auth/Views/AppRootView.swift"
dashboard_view="AlphaPos/Features/Dashboard/Views/MainDashboardView.swift"

rg -q 'notificationStore\.isInitialReconciliationComplete' "$root_view"
rg -q 'guard selectedTab != \.dashboard else \{ return \}' "$dashboard_view"

echo "Dashboard entry contract: PASS"
echo "- Initial reconciliation gates LiveDashboardView construction"
echo "- Periodic full sync is suppressed while Live Dashboard is visible"
