import { Component } from '@angular/core';

@Component({
  selector: 'app-visitor-privacy', standalone: true,
  template: `<article><a href="/showcase">Back to Showcase</a><h1>Visitor privacy</h1>
    <p>When this Showcase is served, we record the request time in UTC, the requested page path, and the public IP address observed by Azure App Service. We use a local GeoIP database to estimate country, state or region, and city. IP addresses are not sent to an external geolocation service.</p>
    <p>This information is used to understand site traffic. Visitor records expire automatically after 90 days. The statistics and IP-address log are restricted to authorized administrators using Microsoft Entra sign-in.</p>
    <p>No analytics cookies, advertising identifiers, page query strings, or browser fingerprints are collected by this implementation. Shared networks, VPNs, bots, and changing IP addresses affect the counts. Locations are approximate and may be unknown.</p>
    <p>Administrative sign-in uses Microsoft authentication cookies. Hosting and identity services may maintain their own operational logs under their separate retention settings. The 90-day visitor-record expiry does not immediately remove records from database backups.</p>
    <p>Location data includes GeoLite2 data created by MaxMind, available from <a href="https://www.maxmind.com">MaxMind</a>. Contact <a href="mailto:myaacoub@microsoft.com">myaacoub&#64;microsoft.com</a> about visitor data.</p>
  </article>`,
  styles: [`article { max-width: 800px; margin: auto; padding: 32px 24px 56px; color: #243a5e; line-height: 1.7; overflow-wrap: anywhere; } h1 { font-size: 28px; } a { color: #0069b8; }`],
})
export class PrivacyPage {}