"use strict";

var page = require('webpage').create(),
    system = require('system'),
    address, output;

if (system.args.length < 3 || system.args.length > 4) {
    console.log('Usage: graph.js IP filename');
    phantom.exit();
} else {
    address = system.args[1];
    output = system.args[2];
    console.log("Fetching", address, "for", output);
    page.viewportSize = { width: 501, height: 233 };
    page.onConsoleMessage = function (msg) {
        console.log('Page msg:', msg);
    };
    page.customHeaders = {
        // "Referer": "http://www.pool.ntp.org/?graphs"
    };
    page.settings.userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/534.57.2 (KHTML, like Gecko) Version/5.1.7 Safari/534.57.2";

    page.open(address, function (status) {
        if (status !== 'success') {
            console.log('Unable to load the address!');
        } else {
            window.setTimeout(function () {
                page.clipRect = { top: 0, left: 20, width: 501, height: 233 };
                page.render(output);
                phantom.exit();
            }, 200);
        }
    });
}
