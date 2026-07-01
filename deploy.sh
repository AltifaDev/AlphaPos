#!/usr/bin/env bash
# deploy.sh — AlphaPos Cloudflare Production Deployment Script
# This compiles the Vite/React assets first, then triggers wrangler deploy.

echo "=================================================="
echo " 🚀 Starting Production Build for Web Frontend... "
echo "=================================================="

# 1. Navigate to the web folder and install production dependencies
cd customer-order-web || exit 1
echo "📦 Installing npm dependencies..."
npm install

# 2. Compile Vite/React assets to dist/
echo "⚙️ Running static assets production build..."
npm run build

# 3. Return to root directory and deploy via Wrangler
cd .. || exit 1
echo "☁️ Deploying to Cloudflare Workers & Assets..."
npx wrangler deploy
