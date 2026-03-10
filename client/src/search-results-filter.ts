/**
 * Search Results Relevance Filter
 *
 * Handles the "Show all results" checkbox functionality for admin search results.
 * When unchecked (default), shows only the most relevant results based on search type.
 * When checked, shows all results.
 */

function initializeSearchResultsFilter(): void {
    const checkbox = document.getElementById('showAllResults') as HTMLInputElement;

    if (!checkbox) {
        return; // No filter checkbox on this page
    }

    // Handle checkbox change
    checkbox.addEventListener('change', function() {
        try {
            const secondaryElements = document.querySelectorAll('.search-result-secondary');
            const action = this.checked ? 'add' : 'remove';

            secondaryElements.forEach(element => {
                element.classList[action]('show-all');
            });
        } catch (error) {
            console.error('Error toggling search results:', error);
        }
    });
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeSearchResultsFilter);
} else {
    initializeSearchResultsFilter();
}
