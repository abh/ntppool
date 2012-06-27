/*! Copyright 2012 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */
/*globals d3:true, Modernizr:true */

$(document).ready(function(){
    "use strict";

    var data = {};
    var graph_div = $('div.graph');

    if (!NP.svg_graphs && !Modernizr.svg) { // no svg support, show the noscript section
        var $legacy = $('#legacy-graphs');

        if (!legacy) { return; }

        $legacy.html('Please upgrade to a browser that supports SVG '
                     + 'to see the new graphs. '
                     + '(For example <a href="http://www.apple.com/safari/">Safari</a>, '
                     + '<a href="https://www.google.com/chrome/">Chrome</a>, '
                     + '<a href="http://www.mozilla.org/firefox">Firefox</a> or '
                     + '<a href="http://ie.microsoft.com/">IE9+</a>)<br>'
                    );

        $legacy.append($('<br><img class=".legacy-graph-img"/>')
            .attr('src', $legacy.data('offset-graph-url')));

        return;
    }

    graph_div.each(function(i) {
        var div = $(this);
        var ip = div.data('server-ip');
        if (ip) {
            var graph_legend = div.next('.graph-legend');

            d3.json("/scores/"+ ip +"/json?monitor=*&limit=400", function(json) {
                if (json) {
                    data[ip] = json;
                    server_chart(div, json, { legend: graph_legend });
                }
                else {
                    div.html('<p>Error downloading graph data</p>');
                }
            });
            return;
        }

        var zone = div.data('zone');
        if (zone) {
            d3.json("/zone/json/" + zone + "?limit=180", function(json) {
                if (json) {
                    data[zone] = json;
                    zone_chart(div, json, { name: zone });

                }
                else {
                    div.html('<p>Error downloading graph data</p>');
                }
            });

        }
    });

});

