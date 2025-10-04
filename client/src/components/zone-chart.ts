/**
 * Zone Chart Web Component
 * Displays NTP server counts over time for a zone
 */

import { BaseChartComponent } from './base-chart.js';
import { createZoneChart } from '@/charts/zone-chart.js';
import type { ZoneCountsResponse } from '@/types/index.js';

/**
 * Zone Chart Component
 * Usage: <ntp-zone-chart zone="us" show-both-versions="true"></ntp-zone-chart>
 */
export class ZoneChartComponent extends BaseChartComponent {
  static override get observedAttributes(): string[] {
    return [...super.observedAttributes, 'zone', 'ip-version', 'show-both-versions'];
  }

  constructor() {
    super();
    // Dimensions controlled by HTML attributes per dimension system refactor
  }

  override connectedCallback(): void {
    // Validate required attributes
    if (!this.validateAttributes()) {
      this.showErrorState('Missing required zone attribute');
      return;
    }

    super.connectedCallback();
  }

  override attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null): void {
    super.attributeChangedCallback(name, oldValue, newValue);

    // Reload chart if zone changes
    if (name === 'zone' && oldValue !== newValue && newValue) {
      if (this.validateAttributes()) {
        this.loadChart();
      } else {
        this.showErrorState('Invalid zone attribute');
      }
    }

    // Re-render if display options change
    if ((name === 'ip-version' || name === 'show-both-versions') && oldValue !== newValue) {
      if (this.data) {
        this.render();
      }
    }
  }

  /**
   * Get the zone name from attributes
   */
  getZone(): string | null {
    return this.getAttribute('zone');
  }

  /**
   * Get the IP version preference
   */
  getIpVersion(): 'v4' | 'v6' {
    const version = this.getAttribute('ip-version');
    return version === 'v6' ? 'v6' : 'v4';
  }

  /**
   * Check if both IP versions should be shown
   */
  shouldShowBothVersions(): boolean {
    return this.getAttribute('show-both-versions') !== 'false';
  }

  /**
   * Set zone and reload chart
   */
  setZone(zone: string): void {
    this.setAttribute('zone', zone);
  }

  /**
   * Set IP version preference
   */
  setIpVersion(version: 'v4' | 'v6'): void {
    this.setAttribute('ip-version', version);
  }

  /**
   * Toggle showing both IP versions
   */
  setShowBothVersions(show: boolean): void {
    this.setAttribute('show-both-versions', show.toString());
  }

  // Protected methods (implementation of abstract methods)

  protected getDataUrl(): string {
    const zone = this.getZone();
    if (!zone) {
      throw new Error('Zone is required');
    }
    return `/zone/${zone}.json?limit=480`;
  }

  protected validateAttributes(): boolean {
    const zone = this.getZone();
    if (!zone) return false;

    // Basic zone name validation
    // Allow alphanumeric, hyphens, dots, and @ for zone names
    const zoneRegex = /^[a-zA-Z0-9.@-]+$/;
    return zoneRegex.test(zone) && zone.length > 0 && zone.length < 100;
  }

  protected render(): void {
    if (!this.data) return;

    this.clearChart();


    try {
      // Create the D3 chart with current settings
      const chartOptions = {
        name: this.getZone() || 'Zone',
        ipVersion: this.getIpVersion(),
        showBothVersions: this.shouldShowBothVersions(),
        width: this.options.width,
        height: this.options.height
      };


      createZoneChart(this.chartContainer, this.data as ZoneCountsResponse, chartOptions);

      // Update container dimensions
      this.updateContainerDimensions();

      // Add zone info display
      this.addZoneInfo();

    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to render chart';
      this.showErrorState(message);
    }
  }


  // Private helper methods

  private updateContainerDimensions(): void {
    const svg = this.chartContainer.querySelector('svg');
    if (svg) {

      // Use fixed dimensions from HTML attributes instead of responsive 100%
      svg.setAttribute('width', this.options.width.toString());
      svg.setAttribute('height', this.options.height.toString());
      svg.setAttribute('viewBox', `0 0 ${this.options.width} ${this.options.height}`);
      svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

    }
  }

  private addZoneInfo(): void {
    // Remove existing zone info
    const existingInfo = this.chartContainer.querySelector('.zone-info');
    if (existingInfo) {
      existingInfo.remove();
    }

    // Add zone information display
    const zoneInfo = document.createElement('div');
    zoneInfo.className = 'zone-info';

    const zone = this.getZone();
    const showBoth = this.shouldShowBothVersions();
    const ipVersion = this.getIpVersion();

    // Add IP version toggle if not showing both
    if (!showBoth) {
      let infoText = `Zone: ${zone}`;
      infoText += ` (IPv${ipVersion === 'v6' ? '6' : '4'})`;
      zoneInfo.textContent = infoText;

      this.chartContainer.appendChild(zoneInfo);

      this.addIpVersionToggle();
    }
  }

  private addIpVersionToggle(): void {
    // Remove existing toggle
    const existingToggle = this.chartContainer.querySelector('.ip-version-toggle');
    if (existingToggle) {
      existingToggle.remove();
    }

    const toggle = document.createElement('div');
    toggle.className = 'ip-version-toggle';

    const v4Button = document.createElement('button');
    v4Button.className = `version-button ${this.getIpVersion() === 'v4' ? 'active' : ''}`;
    v4Button.textContent = 'IPv4';
    v4Button.addEventListener('click', () => {
      this.setIpVersion('v4');
    });

    const v6Button = document.createElement('button');
    v6Button.className = `version-button ${this.getIpVersion() === 'v6' ? 'active' : ''}`;
    v6Button.textContent = 'IPv6';
    v6Button.addEventListener('click', () => {
      this.setIpVersion('v6');
    });

    toggle.appendChild(v4Button);
    toggle.appendChild(v6Button);
    this.chartContainer.appendChild(toggle);
  }
}

// Register the custom element
if (!customElements.get('ntp-zone-chart')) {
  customElements.define('ntp-zone-chart', ZoneChartComponent);
}

// Export for external registration
export { ZoneChartComponent as default };
