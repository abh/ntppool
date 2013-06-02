/*! Copyright 2012-2013 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */
/*globals d3:true, Modernizr:true */

if (!Pool) { var Pool = {}; }
if (!Pool.Graphs) { Pool.Graphs = {}; }

(function() {
    "use strict";
    var g = Pool.Graphs;

    var loadZoneGraph = function(div) {
        var zone = div.data('zone');
        if (zone) {
            d3.json("/zone/" + zone + ".json?limit=180", function(json) {
                if (json) {
                    // data[zone] = json;
                    zone_chart(div, json, { name: zone });
                }
                else {
                    div.html('<p>Error downloading graph data</p>');
                }
            });
        }
    };

    g.LoadGraph = function(div) {
        var ip = div.data('server-ip');
        if (!ip) {
            return loadZoneGraph(div);
        }
        var graph_legend = div.next('.graph-legend');
        var spinner = div.append('<div/>');
        var svg;

        var type = "sample";
        var points = 1000;

        var data_server = "localhost:8085";
        // data_server = "gunnarr.bn.dev:6081";
        // data_server = "data-ntp.pagekite.me";

        var graph_div = $('<div/>');

        var updateGraph = function() {

            spinner.spin({ lines: 12, length: 12, width: 4, radius: 15, left: "250px", top: "40px", color: "#555" });

            var url = "http://" + data_server + "/data/"+ ip +"?points="+points+"&type="+type;
            console.log("loading ", url);
            // d3.json("/scores/"+ ip +"/json?monitor=*&limit=400", function(json) {
            d3.json(url, function(json) {

                spinner.spin(false);
                console.log("SVG", svg);
                graph_div.empty();
                graph_legend.empty();

                if (json) {
                    // data[ip] = json;
                    svg = server_chart(graph_div, json, { legend: graph_legend, svg: svg });
                    // console.log("width/height", div.width(), div.height());
                }
                else {
                    div.html('<p>Error downloading graph data</p>');
                }
            });
        };

        var typeButtons = $('<div class="btn-group" data-toggle="buttons-radio">' +
            '<button type="button" class="btn btn-mini active">sample</button>' +
            '<button type="button" class="btn btn-mini">worst</button>' +
            '<button type="button" class="btn btn-mini" disabled>90%</button>' +
            '</div>'
        );
        div.append(typeButtons);
        typeButtons.find("button").each(function(i, btn) {
            var $btn = $(btn);
            $btn.on('click', null, $btn.text(), function(e) {
                var t = $(e.target);
                if (t.hasClass('active')) {
                    return;
                }
                type = e.data;
                updateGraph();
            });
        });

        var timeButtons = $('<div class="btn-group" data-toggle="buttons-radio"/>');
        jQuery.each(["1 day", "7 days", "1 month", "6 months", "1 year", "All"], function(i,n) {
            var active = n===points ? 'active' : '';
            timeButtons.append('<button type="button" class="btn btn-mini '+active+'">'+n+'</button>');
        });
        timeButtons.find("button").each(function(i, btn) {
            var $btn = $(btn);
            $btn.on('click', null, $btn.text(), function(e) {
                var t = $(e.target);
                if (t.hasClass('active')) {
                    return;
                }
                type = e.data;
                updateGraph();
            });
        });

        var pointsButtons = $('<div class="btn-group" data-toggle="buttons-radio"/>');
        jQuery.each([200,500,1000,2000,4000,8000], function(i,n) {
            var active = n===points ? 'active' : '';
            pointsButtons.append('<button type="button" class="btn btn-mini '+active+'">'+n+'</button>');
        });
        pointsButtons.find("button").each(function(i, btn) {
            var $btn = $(btn);
            $btn.on('click', null, $btn.text(), function(e) {
                var t = $(e.target);
                if (t.hasClass('active')) {
                    return;
                }
                points = e.data;
                updateGraph();
            });
        });


        div.append(graph_div);

        div.append(timeButtons);
        div.append(pointsButtons);

        updateGraph();

        return;
    };

    g.SetupGraphs = function() {

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

            var graph_div = $('div.graph');

            graph_div.each(function(i) {
                var div = $(this);
                g.LoadGraph(div);
            });

        };

        load_graphs();
    };

})();

$(document).ready(function(){
    "use strict";

    Pool.Graphs.SetupGraphs();

});

