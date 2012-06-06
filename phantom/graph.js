var page = require('webpage').create(),
    system = require('system'),
    address, output;

if (system.args.length < 3 || system.args.length > 4) {
    console.log('Usage: graph.js IP filename');
    phantom.exit();
} else {
    address = system.args[1];
    output = system.args[2];
    page.viewportSize = { width: 501, height: 233 };
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
