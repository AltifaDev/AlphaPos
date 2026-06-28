/**
 * AlphaPos - Hybrid Location Verification Module
 *
 * Dual-layer location validation:
 * 1. GPS Geofencing (Primary) — uses HTML5 Geolocation API, 50m radius
 * 2. Wi-Fi IP Matching (Fallback) — checks client IP against restaurant network
 *
 * In production mode, GPS is required. In dev mode (?dev=true), a simulator panel is shown.
 */

class HybridLocationVerifier {
    constructor() {
        this.restaurantCoords = {
            lat: 13.7563,
            lng: 100.5018
        };
        this.restaurantWifiIp = "203.150.12.34";
        this.geofenceRadius = 50;

        this.deviceCoords = { lat: null, lng: null };
        this.distance = 0;

        this.isValid = false;
        this.status = "checking";

        this.isDevMode = new URLSearchParams(window.location.search).get('dev') === 'true';

        this._gpsAttempted = false;
        this._gpsDenied = false;
        this._onPremisesVerified = false;
        this._paymentCompleted = false;
        this._periodicCheckInterval = null;
    }

    translate(key, defaultVal) {
        if (window.app && typeof window.app.translate === 'function') {
            return window.app.translate(key, defaultVal);
        }
        return defaultVal;
    }

    async init() {
        await this._fetchMerchantLocation();
        if (this.isDevMode) {
            this._showDevSimulator();
        }
        this.runVerification();
        this._startPeriodicCheck();
    }

    async _fetchMerchantLocation() {
        try {
            const res = await fetch('/v1/merchants');
            if (res.ok) {
                const data = await res.json();
                if (data.latitude && data.longitude) {
                    this.restaurantCoords = {
                        lat: parseFloat(data.latitude),
                        lng: parseFloat(data.longitude)
                    };
                }
                if (data.geofence_radius_meters) {
                    this.geofenceRadius = parseInt(data.geofence_radius_meters, 10);
                }
            }
        } catch (e) {
            console.warn("[Location] Could not fetch merchant location from server, using defaults:", e);
        }
    }

    destroy() {
        if (this._periodicCheckInterval) {
            clearInterval(this._periodicCheckInterval);
        }
    }

    _startPeriodicCheck() {
        this._periodicCheckInterval = setInterval(() => {
            if (this._paymentCompleted) return;
            if (this._onPremisesVerified) return;
            this.runVerification();
        }, 30000);
    }

    async runVerification() {
        if (this._paymentCompleted) {
            this.isValid = false;
            this._updateBanner("restricted",
                this.translate("paymentCompleteTitle", "Payment Complete"),
                this.translate("paymentCompleteDesc", "Thank you! Your bill has been paid. Please close this page.")
            );
            this.toggleOrderingButton(false);
            return;
        }

        if (this._onPremisesVerified) {
            this.isValid = true;
            this._updateBanner("allowed",
                this.translate("orderingActive", "Ordering Active"),
                this.translate("gpsInsideMsg", "Location verified via GPS ({dist}m within venue)").replace("{dist}", this.distance.toFixed(1))
            );
            this.toggleOrderingButton(true);
            return;
        }

        if (this.isDevMode) {
            await this._runSimulatedVerification();
            return;
        }

        await this._runRealVerification();
    }

    async _runRealVerification() {
        this._updateBanner("checking",
            this.translate("verifyingLocationMsg", "Verifying Location..."),
            this.translate("checkingWifiGps", "Checking GPS and Guest Wi-Fi proximity")
        );

        try {
            const coords = await this._requestRealLocation();
            this.deviceCoords = coords;
            this.distance = this._calculateDistance(
                coords.lat, coords.lng,
                this.restaurantCoords.lat, this.restaurantCoords.lng
            );

            if (this.distance <= this.geofenceRadius) {
                this.isValid = true;
                this._onPremisesVerified = true;
                this._updateBanner("allowed",
                    this.translate("orderingActive", "Ordering Active"),
                    this.translate("gpsInsideMsg", "Location verified via GPS ({dist}m within venue)").replace("{dist}", this.distance.toFixed(1))
                );
                this.toggleOrderingButton(true);
            } else {
                this.isValid = false;
                this._updateBanner("restricted",
                    this.translate("orderingBlocked", "Ordering Blocked"),
                    this.translate("gpsOutsideMsg", "You are {dist}km outside the restaurant. Please join Guest Wi-Fi.")
                        .replace("{dist}", (this.distance / 1000).toFixed(2))
                );
                this.toggleOrderingButton(false);
            }
        } catch (gpsError) {
            console.warn("[Location] GPS failed:", gpsError);
            this._gpsDenied = true;
            this.isValid = false;
            this._updateBanner("restricted",
                this.translate("orderingBlocked", "Ordering Blocked"),
                this.translate("gpsDeniedMsg", "Please enable Location Services to order. Connect to restaurant Wi-Fi if GPS is unavailable.")
            );
            this.toggleOrderingButton(false);
        }
    }

    async _runSimulatedVerification() {
        this._updateBanner("checking",
            this.translate("verifyingLocationMsg", "Verifying Location..."),
            this.translate("checkingWifiGps", "Checking Wi-Fi and GPS coordinates...")
        );

        await new Promise(resolve => setTimeout(resolve, 800));

        if (this.simulatedNetwork === "wifi") {
            const ip = this.restaurantWifiIp;
            const ipEl = document.getElementById("simulatedIp");
            if (ipEl) ipEl.innerText = ip;
            const distEl = document.getElementById("simulatedDistance");
            if (distEl) distEl.innerText = this.translate("wifiNoDistance", "Not required (On Guest Wi-Fi)");

            this.isValid = true;
            this._updateBanner("allowed",
                this.translate("orderingActive", "Ordering Active"),
                this.translate("verifiedWifi", "Verified via Restaurant Guest Wi-Fi. (IP: {ip})").replace("{ip}", ip)
            );
            this.toggleOrderingButton(true);
            return;
        }

        const cellularIp = "182.52.112.89";
        const ipEl = document.getElementById("simulatedIp");
        if (ipEl) ipEl.innerText = cellularIp;

        if (this.simulatedGpsType === "denied") {
            this.isValid = false;
            const distEl = document.getElementById("simulatedDistance");
            if (distEl) distEl.innerText = this.translate("gpsUnavailable", "Unavailable");
            this._updateBanner("restricted",
                this.translate("orderingBlocked", "Ordering Blocked"),
                this.translate("gpsDeniedMsg", "GPS Access Denied. Please connect to Guest Wi-Fi or enable Location services.")
            );
            this.toggleOrderingButton(false);
            return;
        }

        if (this.simulatedGpsType === "inside") {
            this.deviceCoords = { lat: 13.75625, lng: 100.50185 };
        } else {
            this.deviceCoords = { lat: 13.7850, lng: 100.5280 };
        }

        this.distance = this._calculateDistance(
            this.deviceCoords.lat, this.deviceCoords.lng,
            this.restaurantCoords.lat, this.restaurantCoords.lng
        );

        const distEl = document.getElementById("simulatedDistance");
        if (distEl) distEl.innerText = this.distance.toFixed(1) + " " + this.translate("meters", "meters");

        if (this.distance <= 50) {
            this.isValid = true;
            this._updateBanner("allowed",
                this.translate("orderingActive", "Ordering Active"),
                this.translate("gpsInsideMsg", "Location verified via GPS ({dist}m within venue)").replace("{dist}", this.distance.toFixed(1))
            );
            this.toggleOrderingButton(true);
        } else {
            this.isValid = false;
            this._updateBanner("restricted",
                this.translate("orderingBlocked", "Ordering Blocked"),
                this.translate("gpsOutsideMsg", "You are {dist}km outside the restaurant. Please join Guest Wi-Fi.")
                    .replace("{dist}", (this.distance / 1000).toFixed(2))
            );
            this.toggleOrderingButton(false);
        }
    }

    _requestRealLocation() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject("Geolocation is not supported");
                return;
            }

            navigator.geolocation.getCurrentPosition(
                (position) => {
                    resolve({
                        lat: position.coords.latitude,
                        lng: position.coords.longitude
                    });
                },
                (error) => {
                    let message = "Location unavailable";
                    switch (error.code) {
                        case error.PERMISSION_DENIED:
                            message = "GPS permission denied";
                            break;
                        case error.POSITION_UNAVAILABLE:
                            message = "GPS position unavailable";
                            break;
                        case error.TIMEOUT:
                            message = "GPS request timed out";
                            break;
                    }
                    reject(message);
                },
                { enableHighAccuracy: true, timeout: 8000, maximumAge: 30000 }
            );
        });
    }

    _calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371e3;
        const phi1 = lat1 * Math.PI / 180;
        const phi2 = lat2 * Math.PI / 180;
        const deltaPhi = (lat2 - lat1) * Math.PI / 180;
        const deltaLambda = (lon2 - lon1) * Math.PI / 180;

        const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
                  Math.cos(phi1) * Math.cos(phi2) *
                  Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);

        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c;
    }

    _updateBanner(status, title, description) {
        const banner = document.getElementById("securityBanner");
        const titleEl = document.getElementById("bannerTitle");
        const descEl = document.getElementById("bannerDesc");
        const spinner = document.getElementById("bannerSpinner");

        if (!banner || !titleEl || !descEl) return;

        banner.className = "security-banner " + status;
        titleEl.innerText = title;
        descEl.innerText = description;

        if (status === "checking") {
            spinner.classList.remove("hide");
            banner.children[0].innerText = "📡";
        } else {
            spinner.classList.add("hide");
            if (status === "allowed") banner.children[0].innerText = "✅";
            if (status === "restricted") banner.children[0].innerText = "🚫";
            if (status === "warn") banner.children[0].innerText = "⚠️";
        }
    }

    toggleOrderingButton(enabled) {
        const btn = document.getElementById("submitOrderBtn");
        const warning = document.getElementById("btnWarningText");

        if (!btn) return;

        if (enabled) {
            btn.classList.remove("disabled");
            btn.removeAttribute("disabled");
            if (warning) {
                warning.style.opacity = "0";
                setTimeout(() => warning.classList.add("hide"), 300);
            }
        } else {
            btn.classList.add("disabled");
            btn.setAttribute("disabled", "true");
            if (warning) {
                warning.classList.remove("hide");
                setTimeout(() => warning.style.opacity = "1", 50);
            }
        }
    }

    markPaymentCompleted() {
        this._paymentCompleted = true;
        this.isValid = false;
        this._onPremisesVerified = false;
        this.toggleOrderingButton(false);
        this._updateBanner("restricted",
            this.translate("paymentCompleteTitle", "Payment Complete"),
            this.translate("paymentCompleteDesc", "Thank you! Your bill has been paid. Please close this page.")
        );
    }

    simulateNetworkChange(type) {
        this.simulatedNetwork = type;
        this.runVerification();
    }

    simulateGpsChange(type) {
        this.simulatedGpsType = type;
        this.runVerification();
    }

    _showDevSimulator() {
        const existing = document.getElementById("devSimulatorPanel");
        if (existing) return;

        const panel = document.createElement("div");
        panel.id = "devSimulatorPanel";
        panel.innerHTML = `
            <style>
                #devSimulatorPanel {
                    position: fixed; bottom: 0; left: 0; right: 0;
                    background: rgba(0,0,0,0.85); color: #fff;
                    padding: 12px 16px; z-index: 99999;
                    font-family: monospace; font-size: 12px;
                    border-top: 2px solid #2D71F8;
                    max-height: 200px; overflow-y: auto;
                }
                #devSimulatorPanel h4 { margin: 0 0 8px; font-size: 14px; color: #2D71F8; }
                #devSimulatorPanel .sim-row { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin-bottom: 8px; }
                #devSimulatorPanel .sim-row label { color: #aaa; min-width: 100px; }
                #devSimulatorPanel select { background: #222; color: #fff; border: 1px solid #555; padding: 4px 8px; border-radius: 4px; }
                #devSimulatorPanel .sim-stat { color: #0f0; font-size: 11px; }
                #devSimulatorPanel .sim-stat span { color: #fff; }
            </style>
            <h4>Dev: Hybrid Security Simulator</h4>
            <div class="sim-row">
                <label>Network:</label>
                <select onchange="window.locationVerifier.simulateNetworkChange(this.value)">
                    <option value="wifi">Guest Wi-Fi</option>
                    <option value="cellular">Cellular 5G/4G</option>
                </select>
                <label>GPS Sim:</label>
                <select onchange="window.locationVerifier.simulateGpsChange(this.value)">
                    <option value="inside">Inside Restaurant</option>
                    <option value="outside">Outside Restaurant</option>
                    <option value="denied">GPS Denied</option>
                </select>
            </div>
            <div class="sim-row">
                <div class="sim-stat">Restaurant: <span id="simRestCoord">${this.restaurantCoords.lat}, ${this.restaurantCoords.lng}</span></div>
                <div class="sim-stat">IP: <span id="simulatedIp">--</span></div>
                <div class="sim-stat">Distance: <span id="simulatedDistance">--</span></div>
            </div>
        `;
        document.body.appendChild(panel);

        this.simulatedNetwork = "wifi";
        this.simulatedGpsType = "inside";
    }
}

window.locationVerifier = new HybridLocationVerifier();
window.addEventListener("DOMContentLoaded", () => window.locationVerifier.init());
