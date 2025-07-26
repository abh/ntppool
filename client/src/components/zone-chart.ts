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
    // Allow alphanumeric, hyphens, and dots for zone names
    const zoneRegex = /^[a-zA-Z0-9.-]+$/;
    return zoneRegex.test(zone) && zone.length > 0 && zone.length < 100;
  }

  protected render(): void {
    if (!this.data) return;

    this.clearChart();

    console.log('🎯 ZoneChart render() debug:', {
      'this.options': this.options,
      'HTML width attr': this.getAttribute('width'),
      'HTML height attr': this.getAttribute('height'),
      'chartContainer': this.chartContainer,
      'chartContainer.tagName': this.chartContainer.tagName,
      'component element': this,
      'component.tagName': this.tagName
    });

    try {
      // Create the D3 chart with current settings
      const chartOptions = {
        name: this.getZone() || 'Zone',
        ipVersion: this.getIpVersion(),
        showBothVersions: this.shouldShowBothVersions(),
        width: this.options.width,
        height: this.options.height
      };

      console.log('🎯 ZoneChart calling createZoneChart with options:', chartOptions);

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

  protected getComponentStyles(): string {
    const baseStyles = `
      /* Zone chart specific styles */
      .chart-container {
        background: white;
        border-radius: 4px;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        position: relative;
      }

      .zone-info {
        position: absolute;
        top: 0.5rem;
        right: 0.5rem;
        background: rgba(255, 255, 255, 0.9);
        padding: 0.25rem 0.5rem;
        border-radius: 4px;
        font-size: 0.75rem;
        color: #6b7280;
        border: 1px solid #e5e7eb;
        pointer-events: none;
      }

      .ip-version-toggle {
        margin-top: 0.5rem;
        display: flex;
        gap: 0.5rem;
        justify-content: center;
      }

      .version-button {
        padding: 0.25rem 0.75rem;
        border: 1px solid #d1d5db;
        background: white;
        border-radius: 4px;
        font-size: 0.875rem;
        cursor: pointer;
        transition: all 0.2s;
      }

      .version-button:hover {
        background: #f3f4f6;
      }

      .version-button.active {
        background: #3b82f6;
        color: white;
        border-color: #3b82f6;
      }

      /* SVG chart styling - removed responsive overrides to respect fixed dimensions */
      .chart-container svg {
        /* width and height set by updateContainerDimensions() */
        max-width: 100%;
      }

      /* Line styling within SVG */
      .chart-container svg .line {
        fill: none;
        stroke-width: 2;
      }

      .chart-container svg .line.registered_count {
        stroke: #1f77b4;
      }

      .chart-container svg .line.active_count {
        stroke: #2ca02c;
      }

      .chart-container svg .line.inactive_count {
        stroke: #ff7f0e;
      }

      .chart-container svg .line.v6 {
        stroke-dasharray: 5,5;
      }

      /* Legend styling */
      .chart-container svg .legend {
        font-size: 12px;
      }

      .chart-container svg .legend .legend-item:hover {
        opacity: 0.8;
      }

      /* Grid styling */
      .chart-container svg .x-axis line,
      .chart-container svg .y-axis line {
        stroke: #e0e0e0;
        stroke-dasharray: 2,2;
      }

      .chart-container svg .x-axis text,
      .chart-container svg .y-axis text {
        fill: #6b7280;
        font-size: 12px;
      }

      /* Responsive adjustments */
      @container (max-width: 600px) {
        .zone-info {
          position: static;
          margin-bottom: 0.5rem;
          text-align: center;
        }

        .ip-version-toggle {
          margin-top: 0.25rem;
        }

        .version-button {
          font-size: 0.75rem;
          padding: 0.1875rem 0.5rem;
        }
      }
    `;

    // Zone charts don't need as many fallback styles since they don't use Bootstrap tables
    return baseStyles;
  }

  // Private helper methods

  private updateContainerDimensions(): void {
    const svg = this.chartContainer.querySelector('svg');
    if (svg) {
      console.log('🎯 updateContainerDimensions before changes:', {
        'svg.style.width': svg.style.width,
        'svg.getAttribute("width")': svg.getAttribute('width'),
        'this.options.width': this.options.width,
        'this.options.height': this.options.height
      });

      // Use fixed dimensions from HTML attributes instead of responsive 100%
      svg.setAttribute('width', this.options.width.toString());
      svg.setAttribute('height', this.options.height.toString());
      svg.setAttribute('viewBox', `0 0 ${this.options.width} ${this.options.height}`);
      svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

      console.log('🎯 updateContainerDimensions after changes:', {
        'svg.style.width': svg.style.width,
        'svg.style.height': svg.style.height,
        'svg viewBox': svg.getAttribute('viewBox')
      });
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
