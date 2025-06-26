/* Copyright 2006-2013 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */

if (!NP) var NP = {};

(function () {

    "use strict";

    NP.netspeed_updated = function (server_id, data) {
        $('#netspeed_' + server_id).fadeIn(400);
        $('#netspeed_' + server_id).html(data.netspeed);
        $('#zones_' + server_id).html(data.zones);
    };

    NP.update_netspeed = function (server_id, netspeed, auth_token) {
        var pars = { "netspeed": netspeed, "server": server_id, "auth_token": auth_token };
        $('#netspeed_' + server_id).fadeOut(50);
        jQuery.getJSON('/manage/server/update/netspeed', pars,
            function (data, textStatus) {
                NP.netspeed_updated(server_id, data);
            }
        );
    };

    NP.recheck_mode7 = function (server_id) {
        console.log("recheck mode7");
        var span = $('#mode7check_' + server_id);
        var pars = { "server": server_id };
        span.fadeOut(50);
        jQuery.getJSON('/manage/server/update/mode7check', pars,
            function (data, textStatus) {
                span.fadeIn(100);
                span.html("Check has been scheduled<br>");
            }
        );
    };

    $(document).ready(function () {
        $("#busy").ajaxStart(function () {
            $(this).show(70);
        })
            .ajaxStop(function () {
                $(this).hide(70);
            });
    });

}());


// htmx configuration
document.addEventListener('DOMContentLoaded', function () {
    if (window.htmx) {
        // htmx.config.defaultSwapStyle = 'outerHTML';
        // htmx.config.refreshOnHistoryMiss = true;
        htmx.config.historyCacheSize = 20;
        htmx.config.includeIndicatorStyles = false;
    }
});

// Monitor configuration error handler for HTMX
function showMonitorConfigError(event) {
    console.log('showMonitorConfigError called', event);
    var xhr = event.detail.xhr;
    console.log('XHR object:', xhr);
    console.log('XHR status:', xhr.status);
    console.log('XHR response:', xhr.responseText);

    var errorDiv = document.getElementById('monitor-config-error');
    var messageSpan = document.getElementById('monitor-config-error-message');
    var traceidSpan = document.getElementById('monitor-config-error-traceid');

    if (!errorDiv || !messageSpan || !traceidSpan) {
        console.error('Monitor config error elements not found');
        return;
    }

    // Debug all response headers
    console.log('All response headers:', xhr.getAllResponseHeaders());

    // Extract error message and trace ID
    var message = 'Server error occurred';
    var traceid = xhr.getResponseHeader('TraceID') || xhr.getResponseHeader('traceid') || xhr.getResponseHeader('Traceid') || 'Not available';
    console.log("traceid attempts: ", {
        TraceID: xhr.getResponseHeader('TraceID'),
        traceid: xhr.getResponseHeader('traceid'),
        Traceid: xhr.getResponseHeader('Traceid')
    });

    // Try to parse JSON response for more detailed error
    try {
        var response = JSON.parse(xhr.responseText);
        if (response && response.error) {
            message = response.error;
        } else if (response && response.message) {
            message = response.message;
        }
    } catch (e) {
        // If not JSON, use status text or default message
        if (xhr.statusText) {
            message = xhr.statusText;
        }
    }

    // Show the error
    messageSpan.textContent = message;
    traceidSpan.textContent = traceid;
    errorDiv.classList.remove('d-none');

    // Scroll to error message
    errorDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}
