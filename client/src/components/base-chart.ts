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
  protected chartContainer: HTMLDivElement;
  protected isLoading = false;
  protected hasError = false;
  protected data: any = null;
  protected resizeObserver: ResizeObserver | undefined;

  // Shadow DOM infrastructure kept as stubs for future reusable component use
  protected shadow?: ShadowRoot; // Unused - kept for future Shadow DOM implementation
  protected styleElement?: HTMLStyleElement; // Unused - kept for future Shadow DOM implementation
  protected useShadowDOM: boolean; // Always false in current usage

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

    // Currently always inherit styles from page CSS (inherit-styles="true" in all templates)
    // Shadow DOM infrastructure kept as minimal stubs for future reusable component use
    this.useShadowDOM = false; // Always false in current usage

    // Create base structure - always use direct DOM attachment
    this.chartContainer = document.createElement('div');
    this.chartContainer.className = 'chart-container';
    this.appendChild(this.chartContainer);

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

      // Inherit-styles attribute kept for future Shadow DOM support
      if (name === 'inherit-styles') {
        // Currently always inherit styles, attribute changes have no effect
        // This branch kept as stub for future Shadow DOM implementation
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
   * Currently always true, but kept for future reusable component use
   */
  shouldInheritStyles(): boolean {
    return this.getAttribute('inherit-styles') !== 'false'; // Default to true
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
   * Currently unused - stub for future Shadow DOM support
   */
  protected getBaseStyles(): string {
    // All styles are inherited from page CSS (see _components.scss)
    // This method kept as stub for future Shadow DOM implementation
    return '';
  }

  /**
   * Update styles when component styles change
   * Currently unused - stub for future Shadow DOM support
   */
  protected updateStyles(): void {
    // All styles are inherited from page CSS
    // This method kept as stub for future Shadow DOM implementation
  }

  /**
   * Extract and return inherited page styles when inherit-styles="true"
   * Currently unused - stub for future Shadow DOM support
   */
  protected getInheritedStyles(): string {
    // All styles are inherited from page CSS
    // This method kept as stub for future Shadow DOM implementation
    return '';
  }

}
