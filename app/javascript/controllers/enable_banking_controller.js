import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="enable-banking"
export default class extends Controller {
  connect() {
    // Initialize Enable Banking integration
    console.log("Enable Banking controller connected")
  }

  // Handle the callback from Enable Banking
  handleCallback(event) {
    const code = event.detail.code
    if (code) {
      // Store the authorization code
      sessionStorage.setItem('enable_banking_auth_code', code)
      
      // Redirect to account creation
      window.location.href = "/accounts/new"
    }
  }
} 