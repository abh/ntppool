/**
 * Base Chart Component
 * Abstract base class for all NTP Pool chart web components
 */

import {
  fetchChartData,
  showLoading,
  showError,
  clearContainer,
  debounce
} from '@/utils/chart-utils.js';
import type { FetchResult } from '@/types/index.js';

export interface ChartComponentOptions {
  width?: number;
  height?: number;
  autoLoad?: boolean;
  retryCount?: number;
  retryDelay?: number;
}

/**
 * Abstract base class for chart web components
 */
export abstract class BaseChartComponent extends HTMLElement {
  protected shadow?: ShadowRoot;
  protected chartContainer: HTMLDivElement;
  protected styleElement?: HTMLStyleElement;
  protected isLoading = false;
  protected hasError = false;
  protected data: any = null;
  protected resizeObserver: ResizeObserver | undefined;
  protected useShadowDOM: boolean;

  // Default options (dimensions set by HTML attributes)
  protected options: Required<ChartComponentOptions> = {
    width: 500,  // Final fallback only
    height: 246, // Final fallback only
    autoLoad: true,
    retryCount: 3,
    retryDelay: 1000
  };

  constructor() {
    super();

    // Determine if we should use shadow DOM or inherit styles
    this.useShadowDOM = !this.shouldInheritStyles();

    // Create base structure
    this.chartContainer = document.createElement('div');
    this.chartContainer.className = 'chart-container';

    if (this.useShadowDOM) {
      // Create shadow DOM for encapsulation
      this.shadow = this.attachShadow({ mode: 'open' });

      this.styleElement = document.createElement('style');
      this.styleElement.textContent = this.getBaseStyles();

      this.shadow.appendChild(this.styleElement);
      this.shadow.appendChild(this.chartContainer);
    } else {
      // No shadow DOM - styles will be inherited from page
      this.appendChild(this.chartContainer);
    }

    // Set up resize handling
    this.setupResizeObserver();
  }

  /**
   * Observed attributes for reactivity
   */
  static get observedAttributes(): string[] {
    return ['width', 'height', 'auto-load', 'inherit-styles'];
  }

  /**
   * Called when component is connected to DOM
   */
  connectedCallback(): void {
    this.updateOptionsFromAttributes();


    if (this.options.autoLoad) {
      this.loadChart();
    }
  }

  /**
   * Called when component is disconnected from DOM
   */
  disconnectedCallback(): void {
    this.cleanup();
  }

  /**
   * Called when observed attributes change
   */
  attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null): void {
    if (oldValue !== newValue) {
      this.updateOptionsFromAttributes();

      // Reload chart if dimensions change
      if ((name === 'width' || name === 'height') && this.data) {
        this.safeRender();
      }

      // Update styles if inherit-styles changes
      if (name === 'inherit-styles') {
        if (this.useShadowDOM) {
          this.updateStyles();
        }
      }
    }
  }

  /**
   * Public method to load chart data
   */
  async loadChart(): Promise<void> {
    if (this.isLoading) return;

    this.isLoading = true;
    this.hasError = false;
    this.showLoadingState();

    try {
      const url = this.getDataUrl();
      const result = await this.fetchWithRetry(url);

      if (result.success && result.data) {
        this.data = result.data;
        this.safeRender();
        this.dispatchEvent(new CustomEvent('chart-loaded', {
          detail: { data: this.data }
        }));
      } else {
        this.showErrorState(result.error || 'Failed to load chart data');
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error occurred';
      this.showErrorState(message);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Public method to refresh chart data
   */
  async refresh(): Promise<void> {
    this.data = null;
    await this.loadChart();
  }

  /**
   * Update chart dimensions
   */
  setDimensions(width: number, height: number): void {
    this.setAttribute('width', width.toString());
    this.setAttribute('height', height.toString());
  }

  /**
   * Get current chart data
   */
  getData(): any {
    return this.data;
  }

  /**
   * Check if styles should be inherited from the page
   */
  shouldInheritStyles(): boolean {
    return this.getAttribute('inherit-styles') === 'true';
  }

  // Abstract methods to be implemented by subclasses

  /**
   * Get the URL for fetching chart data
   */
  protected abstract getDataUrl(): string;

  /**
   * Validate that required attributes are present
   */
  protected abstract validateAttributes(): boolean;

  /**
   * Render the chart with current data
   */
  protected abstract render(): void;

  /**
   * Safe render wrapper with error boundary
   */
  protected safeRender(): void {
    try {
      this.render();
    } catch (error) {
      this.handleRenderError(error);
    }
  }

  /**
   * Handle render errors with user-friendly messaging
   */
  private handleRenderError(error: unknown): void {
    console.error('Chart render error:', error);

    const errorMessage = error instanceof Error ? error.message : 'Chart rendering failed';
    this.showErrorState(`Rendering error: ${errorMessage}`);

    this.dispatchEvent(new CustomEvent('chart-render-error', {
      detail: {
        error: errorMessage,
        originalError: error
      }
    }));
  }

  /**
   * Get component-specific CSS styles
   */
  protected abstract getComponentStyles(): string;

  // Protected helper methods

  /**
   * Update options from component attributes
   */
  protected updateOptionsFromAttributes(): void {
    const width = this.getAttribute('width');
    const height = this.getAttribute('height');
    const autoLoad = this.getAttribute('auto-load');

    if (width) this.options.width = parseInt(width, 10);
    if (height) this.options.height = parseInt(height, 10);
    if (autoLoad !== null) this.options.autoLoad = autoLoad !== 'false';
  }

  /**
   * Fetch data with retry logic
   */
  protected async fetchWithRetry<T>(url: string): Promise<FetchResult<T>> {
    let lastError: string | undefined;

    for (let attempt = 1; attempt <= this.options.retryCount; attempt++) {
      const result = await fetchChartData<T>(url);

      if (result.success) {
        return result;
      }

      lastError = result.error;

      if (attempt < this.options.retryCount) {
        await new Promise(resolve => setTimeout(resolve, this.options.retryDelay * attempt));
      }
    }

    return { success: false, error: lastError || 'Failed after retries' };
  }

  /**
   * Show loading state
   */
  protected showLoadingState(): void {
    showLoading(this.chartContainer, 'Loading chart...');
  }

  /**
   * Show error state
   */
  protected showErrorState(message: string): void {
    this.hasError = true;
    showError(this.chartContainer, message);
    this.dispatchEvent(new CustomEvent('chart-error', {
      detail: { error: message }
    }));
  }

  /**
   * Clear chart container
   */
  protected clearChart(): void {
    clearContainer(this.chartContainer);
  }

  /**
   * Set up resize observer for responsive behavior
   */
  protected setupResizeObserver(): void {
    if (typeof ResizeObserver !== 'undefined') {
      this.resizeObserver = new ResizeObserver(debounce(() => {
        if (this.data && !this.isLoading) {
          this.safeRender();
        }
      }, 250));

      this.resizeObserver.observe(this);
    }
  }

  /**
   * Clean up resources
   */
  protected cleanup(): void {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = undefined;
    }

    // Clean up other resources
    this.data = null;
    this.isLoading = false;
    this.hasError = false;
    this.clearChart();
  }

  /**
   * Get base CSS styles for all chart components
   */
  protected getBaseStyles(): string {
    if (!this.useShadowDOM) {
      // When not using shadow DOM, return minimal styles
      // Most styling will be inherited from the page
      return `
        .chart-container {
          width: 100%;
          height: 100%;
          position: relative;
          min-height: 200px;
        }

        .chart-loading {
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 2rem;
          color: #666;
        }

        .chart-loading .spinner {
          width: 1rem;
          height: 1rem;
          border: 2px solid #e5e7eb;
          border-top: 2px solid #3b82f6;
          border-radius: 50%;
          animation: chart-spinner-spin 1s linear infinite;
          margin-right: 0.5rem;
        }

        @keyframes chart-spinner-spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }

        ${this.getComponentStyles()}
      `;
    }

    // Shadow DOM styles
    return `
      :host {
        display: block;
        width: 100%;
        min-height: 200px;
        position: relative;
        font-family: system-ui, -apple-system, sans-serif;
      }

      .chart-container {
        width: 100%;
        height: 100%;
        position: relative;
      }

      .chart-loading {
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 2rem;
        color: #666;
      }

      .chart-loading .spinner {
        width: 1rem;
        height: 1rem;
        border: 2px solid #e5e7eb;
        border-top: 2px solid #3b82f6;
        border-radius: 50%;
        animation: spin 1s linear infinite;
        margin-right: 0.5rem;
      }

      .alert {
        padding: 0.75rem 1rem;
        border: 1px solid transparent;
        border-radius: 0.375rem;
        margin: 1rem 0;
      }

      .alert-warning {
        color: #92400e;
        background-color: #fef3c7;
        border-color: #f59e0b;
      }

      @keyframes spin {
        0% { transform: rotate(0deg); }
        100% { transform: rotate(360deg); }
      }

      /* Responsive behavior */
      @container (max-width: 480px) {
        :host {
          min-height: 180px;
        }
      }

      ${this.getInheritedStyles()}
      ${this.getComponentStyles()}
    `;
  }

  /**
   * Update styles when component styles change
   */
  protected updateStyles(): void {
    if (this.useShadowDOM && this.styleElement) {
      this.styleElement.textContent = this.getBaseStyles();
    }
  }

  /**
   * Extract and return inherited page styles when inherit-styles="true"
   */
  protected getInheritedStyles(): string {
    // When not using shadow DOM, styles are inherited naturally
    // Only return styles when using shadow DOM with inheritance
    if (!this.useShadowDOM || !this.shouldInheritStyles()) {
      return '';
    }

    // Simplified inheritance - just basic fallback styles for shadow DOM
    return `
      /* Basic inherited styles for shadow DOM with inheritance */
      :host {
        font-size: inherit;
        font-family: inherit;
        color: inherit;
      }
    `;
  }

}
