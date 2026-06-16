/**
 * AlphaPos - Hybrid Location Verification Module
 * 
 * Implements a dual-layer location validation:
 * 1. Wi-Fi SSID / Public IP matching (Instantly allows ordering if on guest Wi-Fi)
 * 2. GPS Geofencing (Fallback if on cellular, verifying device is within 50m of branch)
 */

class HybridLocationVerifier {
    constructor() {
        // Restaurant Location Settings (AlphaPos Bangkok Branch)
        this.restaurantCoords = {
            lat: 13.7563,
            lng: 100.5018
        };
        this.restaurantWifiIp = "203.150.12.34";
        
        // Default simulated device states
        this.simulatedNetwork = "wifi"; // 'wifi' | 'cellular'
        this.simulatedGpsType = "inside"; // 'inside' | 'outside' | 'denied'
        
        // Real Location Data (if fetched)
        this.deviceCoords = { lat: null, lng: null };
        this.distance = 0;
        
        // Verification results
        this.isValid = false;
        this.status = "checking"; // 'checking' | 'allowed' | 'restricted' | 'warn'
    }

    translate(key, defaultVal) {
        if (window.app && typeof window.app.translate === 'function') {
            return window.app.translate(key, defaultVal);
        }
        return defaultVal;
    }

    init() {
        // Run initial verification
        this.runVerification();
    }

    /**
     * Runs the location check based on current network and GPS configurations
     */
    async runVerification() {
        this.updateBanner("checking", this.translate("verifyingLocationMsg", "Verifying location..."), this.translate("checkingWifiGps", "Checking Wi-Fi and GPS coordinates..."));
        
        // Delay to simulate network latency
        await new Promise(resolve => setTimeout(resolve, 800));

        // 1. Check Wi-Fi Layer First (IP Check)
        if (this.simulatedNetwork === "wifi") {
            const ip = this.restaurantWifiIp;
            const ipEl = document.getElementById("simulatedIp");
            if (ipEl) ipEl.innerText = ip;
            const distEl = document.getElementById("simulatedDistance");
            if (distEl) distEl.innerText = this.translate("wifiNoDistance", "Not required (On Guest Wi-Fi)");
            
            this.isValid = true;
            this.updateBanner(
                "allowed", 
                this.translate("orderingActive", "Ordering Active"), 
                this.translate("verifiedWifi", "🟢 Verified via Restaurant Guest Wi-Fi. (IP: {ip})").replace("{ip}", ip)
            );
            this.toggleOrderingButton(true);
            return;
        }

        // 2. Fallback to Cellular / GPS Layer
        const cellularIp = "182.52.112.89"; // Simulated cellular carrier IP
        const ipEl = document.getElementById("simulatedIp");
        if (ipEl) ipEl.innerText = cellularIp;

        if (this.simulatedGpsType === "denied") {
            this.isValid = false;
            const distEl = document.getElementById("simulatedDistance");
            if (distEl) distEl.innerText = this.translate("gpsUnavailable", "Unavailable");
            this.updateBanner(
                "restricted", 
                this.translate("orderingBlocked", "Ordering Blocked"), 
                this.translate("gpsDeniedMsg", "🔴 GPS Access Denied. Please connect to Guest Wi-Fi or enable Location services.")
            );
            this.toggleOrderingButton(false);
            return;
        }

        // Setup coordinates based on simulation or browser API
        if (this.simulatedGpsType === "inside") {
            // Inside restaurant coordinates (~10 meters away)
            this.deviceCoords = {
                lat: 13.75625,
                lng: 100.50185
            };
        } else if (this.simulatedGpsType === "outside") {
            // Far away coordinates (~4.4 km away)
            this.deviceCoords = {
                lat: 13.7850,
                lng: 100.5280
            };
        }

        // Calculate Distance
        this.distance = this.calculateDistance(
            this.deviceCoords.lat, 
            this.deviceCoords.lng, 
            this.restaurantCoords.lat, 
            this.restaurantCoords.lng
        );

        const distEl = document.getElementById("simulatedDistance");
        if (distEl) distEl.innerText = this.distance.toFixed(1) + " " + this.translate("meters", "meters");

        // Validate Distance limit (50 meters Geofence)
        if (this.distance <= 50) {
            this.isValid = true;
            this.updateBanner(
                "allowed", 
                this.translate("orderingActive", "Ordering Active"), 
                this.translate("gpsInsideMsg", "🟢 Location verified via GPS ({dist}m within venue)").replace("{dist}", this.distance.toFixed(1))
            );
            this.toggleOrderingButton(true);
        } else {
            this.isValid = false;
            this.updateBanner(
                "restricted", 
                this.translate("orderingBlocked", "Ordering Blocked"), 
                this.translate("gpsOutsideMsg", "🔴 You are {dist}km outside the restaurant. Please join Guest Wi-Fi.").replace("{dist}", (this.distance / 1000).toFixed(2))
            );
            this.toggleOrderingButton(false);
        }
    }

    /**
     * Calculate Distance in meters using Haversine formula
     */
    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371e3; // Earth radius in meters
        const phi1 = lat1 * Math.PI / 180;
        const phi2 = lat2 * Math.PI / 180;
        const deltaPhi = (lat2 - lat1) * Math.PI / 180;
        const deltaLambda = (lon2 - lon1) * Math.PI / 180;

        const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
                  Math.cos(phi1) * Math.cos(phi2) *
                  Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
                  
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c; // Distance in meters
    }

    /**
     * Request actual device GPS coordinates using HTML5 Location API
     */
    requestRealLocation() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject("Geolocation is not supported by your browser");
                return;
            }

            navigator.geolocation.getCurrentPosition(
                (position) => {
                    this.deviceCoords = {
                        lat: position.coords.latitude,
                        lng: position.coords.longitude
                    };
                    resolve(this.deviceCoords);
                },
                (error) => {
                    reject(error.message);
                },
                { enableHighAccuracy: true, timeout: 5000 }
            );
        });
    }

    /**
     * Update UI Banner
     */
    updateBanner(status, title, description) {
        const banner = document.getElementById("securityBanner");
        const titleEl = document.getElementById("bannerTitle");
        const descEl = document.getElementById("bannerDesc");
        const spinner = document.getElementById("bannerSpinner");

        // Clean previous states
        banner.className = "security-banner " + status;
        titleEl.innerText = title;
        descEl.innerText = description;

        // Show/Hide spinner
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

    /**
     * Enable/Disable cart submit button based on verification
     */
    toggleOrderingButton(enabled) {
        const btn = document.getElementById("submitOrderBtn");
        const warning = document.getElementById("btnWarningText");

        if (enabled) {
            btn.classList.remove("disabled");
            btn.removeAttribute("disabled");
            warning.style.opacity = "0";
            setTimeout(() => warning.classList.add("hide"), 300);
        } else {
            btn.classList.add("disabled");
            btn.setAttribute("disabled", "true");
            warning.classList.remove("hide");
            setTimeout(() => warning.style.opacity = "1", 50);
        }
    }

    /**
     * Simulate network change from simulator panel
     */
    simulateNetworkChange(type) {
        this.simulatedNetwork = type;
        this.runVerification();
    }

    /**
     * Simulate GPS location change from simulator panel
     */
    simulateGpsChange(type) {
        this.simulatedGpsType = type;
        this.runVerification();
    }
}

// Instantiate verifier globally
window.locationVerifier = new HybridLocationVerifier();
window.addEventListener("DOMContentLoaded", () => window.locationVerifier.init());
