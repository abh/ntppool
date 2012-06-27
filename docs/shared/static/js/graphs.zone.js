/* Copyright 2012 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */
/*globals d3:true */

function zone_chart(div, data, options) {
    "use strict";

    if (!options) { options = {}; }
    if (!options.ip_version) {
        options.ip_version = 'v4';
    }

    var history = data.history;

    $.each(history, function(i,d) {
        d.date = new Date(d.ts * 1000);
    });

    var y_max = d3.max(history.map(function(e){ return e.rc })),
        y_min = 0;

    if (y_max < 5) {
        y_max = y_max + 1;
    }

    var w = ($(div).data("width")  || 480),
        h = ($(div).data("height") || 246),
        pad_w = 40,
        pad_h = 19,

        y = d3.scale.linear().domain([y_max, y_min ]).range([0, h]),

        x = d3.time.scale.utc().domain([d3.min(history.map(function(e){ return e.date; })),
                                        d3.max(history.map(function(e){ return e.date; }))
            ])
            .range([0, w]);

    var svg = d3.select(div.get(0))
        .append("svg")
        .attr("width", w + pad_w * 2)
        .attr("height", h + pad_h * 2)
        .append("g")
        .attr("transform", "translate(" + pad_w + "," + pad_h + ")");

    var xrule = svg.selectAll("g.x")
        .data(x.ticks(8))
        .enter().append("g")
        .attr("class", "x");

    xrule.append("line")
        .attr("x1", x)
        .attr("x2", x)
        .attr("y1", 0)
        .attr("y2", h);

    xrule.append("text")
        .attr("x", x)
        .attr("y", h + 3)
        .attr("dy", ".71em")
        .attr("text-anchor", "middle")
        .text(x.tickFormat(10));

    /* offset y lines */
    var y_ticks = y_max > 8 ? 8 : y_max;
    var yrule = svg.selectAll("g.y")
        .data(y.ticks(y_ticks))
        .enter().append("g")
        .attr("class", "y");

    yrule.append("line")
        .attr("x1", 0)
        .attr("x2", w)
        .attr("y1", y)
        .attr("y2", y);

    yrule.append("text")
        .attr("x", -3)
        .attr("y", y)
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .text(function(ms) { return y.tickFormat(0)(ms); });


    svg.append("rect")
        .attr("width", w)
        .attr("height", h);

    $.each(['v4', 'v6'], function(i, ip_version) {

        var _class = function(type, name) {
            return [type, name, name+ip_version, ip_version].join(" ");
        }

        var dh = data.history.filter(function(d) { return d.iv === ip_version ? true : false; });

        svg.selectAll(".registered_count" + ip_version)
        .data([dh])
        .enter().append("path")
        .attr("class", _class("line", "registered_count"))
        .attr("d", d3.svg.line()
              .x(function(d) { return x(d.date); })
              .y(function(d) { return y(d.rc); })
              .interpolate("monotone")
             );

        svg.selectAll(".active_count" + ip_version)
        .data([dh])
        .enter().append("path")
        .attr("class", _class("line", "active_count"))
        .attr("d", d3.svg.line()
              .x(function(d) { return x(d.date); })
              .y(function(d) { return y(d.ac); })
              .interpolate("monotone")
        );

        svg.selectAll(".inactive_count" + ip_version)
        .data([dh])
        .enter().append("path")
        .attr("class", _class("line", "inactive_count"))
        .attr("d", d3.svg.line()
              .x(function(d) { return x(d.date); })
              .y(function(d) { return y(d.rc-d.ac); })
              .interpolate("monotone")
        );

    });

   // -----------------------------
   // Add Title then Legend
   // -----------------------------
   svg.append("svg:text")
       .attr("x", 2)
       .attr("y", -5)
       .style("font-weight", "bold")
       .text("Server counts for " + options.name);

}
