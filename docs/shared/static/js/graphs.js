/*! Copyright 2012-2013 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */
/*globals d3:true, Modernizr:true */

if (!Pool) { var Pool = {}; }
if (!Pool.Graphs) { Pool.Graphs = {}; }

(function() {
    "use strict";
    var g = Pool.Graphs;

    g.SetupGraphs = function() {

        var data = {};
        var graph_div = $('div.graph');

        if (!NP.svg_graphs && !Modernizr.svg) { // no svg support, show the noscript section
            var $legacy = $('#legacy-graphs');

            if (!$legacy) { return; }

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
        var load_graphs = function() {

            graph_div.each(function(i) {
                var div = $(this);
                var ip = div.data('server-ip');
                if (ip) {
                    var graph_legend = div.next('.graph-legend');
                    var spinner = div.append('<div/>');
                    spinner.spin({ lines: 12, length: 12, width: 4, radius: 15, left: "250px", top: "20px", color: "#555" });

                    d3.json("/scores/"+ ip +"/json?monitor=*&limit=400", function(json) {
                        spinner.spin(false);

                        if (json) {
                            data[ip] = json;
                            server_chart(div, json, { legend: graph_legend });
                            // console.log("width/height", div.width(), div.height());
                        }
                        else {
                            div.html('<p>Error downloading graph data</p>');
                        }
                    });
                    return;
                }

                var zone = div.data('zone');
                if (zone) {
                    d3.json("/zone/" + zone + ".json?limit=240", function(json) {
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

        };

        load_graphs();
    };

})();

$(document).ready(function(){
    "use strict";

    Pool.Graphs.SetupGraphs();

});

