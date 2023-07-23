/* Copyright 2012-2013 Ask Bjørn Hansen, Develooper LLC & NTP Pool Project */
/*jshint jquery:true browser:true */
/*globals d3:true */

function server_chart(div, data, options) {
    "use strict";

    // console.log("server chart");

    if (!options) { options = {}; }
    var legend = options.legend;

    var history = data.history;

    $.each(history, function(i,d) {
        d.date = new Date(d.ts * 1000);
    });

    var y_offset_max = d3.max(history.map(function(e){ return e.offset * 1; })),
        y_offset_min = d3.min(history.map(function(e){ return e.offset * 1; }));

    // more than two seconds off and we'll stop showing just how bad
    if (y_offset_max >  2) { y_offset_max =  2; }
    if (y_offset_min < -2) { y_offset_min = -2; }

    $(".graph_desc").show();

    var w = ($(div).data("width")  || ($(div).width() * 0.7) || 500),
        h = ($(div).data("height") || ($(div).height()) || 246),
        pad_w = 45,
        pad_h = 19,

        y_offset = d3.scalePow().exponent(0.5).domain([y_offset_max, y_offset_min]).range([0, h]).clamp(true),
        y_score = d3.scaleSqrt().domain([25,-105]).range([0,h]),

        x = d3.scaleUtc().domain([d3.min(history.map(function(e){ return e.date; })),
                                        d3.max(history.map(function(e){ return e.date; }))
            ])
            .range([0, w]);

    // console.log("w", w);
    // console.log("h", h);

    var svg = d3.select(div.get(0))
        .append("svg")
        .attr("width", w + pad_w * 2)
        .attr("height", h + pad_h * 2)
        .append("g")
        .attr("transform", "translate(" + pad_w + "," + pad_h + ")");

    var xticks = 6;

    var xrule = svg.selectAll("g.x")
        .data(x.ticks(xticks))
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
        .text(x.tickFormat(xticks));

    /* offset y lines */
    var yrule = svg.selectAll("g.y")
        .data(y_offset.ticks(8))
        .enter().append("g")
        .attr("class", "y");

    yrule.append("line")
        .attr("x1", 0)
        .attr("x2", w)
        .attr("y1", y_offset)
        .attr("y2", y_offset);

    // legend in fractional milliseconds if offets are less than 3ms
    var yformat = d3.format((y_offset_max*1000 < 3 && y_offset_min*1000 > -3) ? "0.1f" : "0.0f");

    yrule.append("text")
        .attr("x", -4)
        .attr("y", y_offset)
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .text(function(ms) {
            ms = ms * 1000;
            var s = yformat(ms);
            var previous = this.parentNode.previousSibling;
            if (previous.className && previous.className.baseVal === "y") {
                // \xa0 is non breaking space
                return `\xa0${s}`;
            } else {
                // return `${s} ms`;
                return "ms";
            }
        })
        .attr("font-weight", function(ms) {
            // console.log("font-weight", ms);
            if (this.textContent === "ms") {
                return "bold";
            }
            return "";
        });

    /* score y lines */
    var yrule_score = svg.selectAll("g.y_scores")
        .data([20,0,-20,-50,-100])
        .enter().append("g")
        .attr("class", "y_score");

    yrule_score.append("line")
        .attr("x1", 0)
        .attr("x2", w)
        .attr("y1", y_score)
        .attr("y2", y_score);

    yrule_score.append("text")
        .attr("x", w + 30)
        .attr("y", y_score)
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .text(function(text) { return text; });


    var zero_offset = svg.selectAll("g.zero_offset")
        .data([0])
        .enter().append("g");

    zero_offset.append("line")
         .attr("x1", 0)
         .attr("x2", w)
         .attr("y1", y_offset(0))
         .attr("y2", y_offset(0))
         .attr("class", "x")
         .attr("stroke-width", 2)
         .attr("stroke", "black");

    svg.append("rect")
        .attr("width", w)
        .attr("height", h);

    svg.selectAll("g.scores")
        .data(data.history)
        .enter().append("circle")
        .filter(function(d) { return d.monitor_id ? true : false; })
        .attr("class", "scores monitor_data")
        .attr("r", 2)
        .attr("transform", function(d,i) {
            var tr = "translate(" + x(d.date) + "," + y_score(d.score) + ")";
            return tr;
        })
        .style("fill", function(d) {
            if (!d.monitor_id) {
                return "black";
            }
            if (d.step < -1) {
               return "red";
            }
            else if (d.step < 0) {
               return "orange";
            }
            else {
               return "steelblue";
            }
        })
        .on('mouseover',  fade(0.2))
        .on('mouseout',   fade(1));

    svg.selectAll("g.offsets")
        .data(data.history)
        .enter()
        .append("circle")
        .filter(function(d) { return d.monitor_id ? true : false; })
        .attr("class", "offsets monitor_data")
        .attr("r", 1.5) // todo: make this 2 if number of data points are < 250 or some such
        .attr("transform", function(d,i) { return "translate(" + x(d.date) + "," + y_offset(d.offset) + ")"; })
        .style("fill", function(d) {
            var offset = d.offset;

            if (offset < 0) { offset = offset * -1; }
            if ( offset < 0.050 ) {
                return "green";
            }
            else if ( offset < 0.100 ) {
                return "orange";
            }
            else {
                return "red";
           }
        })
        .on('mouseover',  fade(0.25))
        .on('mouseout',   fade(1));

    var dh = data.history.filter(function(d) { return d.monitor_id === null ? true : false; });
    //console.log("d.history", dh);

    svg.selectAll(".total_score")
        .data([dh])
        .enter().append("path")
        .attr("class", "line total_score")
        .style("fill", "none")
        .style("stoke", "red")
        .style("stroke-width", 2)
        .attr("d", d3.line()
              .x(function(d) { return x(d.date); })
              .y(function(d) { return y_score(d.score); })
             );

   // Add Title then Legend
   svg.append("svg:text")
       .attr("x", 0)
       .attr("y", -5)
       .style("font-weight", "bold")
       .text("Offset and scores for " + data.server.ip);

    if (legend) {
        legend.css("margin-left", pad_w);
        legend.css("width", "50%");
        // legend.append('<span class="legend_header">Monitoring Station:</span>');
        var table = $('<table>').addClass('legend table table-striped table-hover table-sm')

        var monitors = data.monitors.sort(function compareFn(a, b) {
            if (a.type == b.type) {
                if (a.status > b.status) {
                    return 1;
                }
                if (b.status > a.status) {
                    return -1;
                }
                if (a.score_ts > b.score_ts) {
                    return 1;
                }
                if (b.score_ts > a.score_ts) {
                    return -1;
                }
                return 0;
            }
            if (a.type > b.type) {
                return -1;
            } else {
                return 1;
            }
        });


        var currentStatus = "";

        for (var i = 0; i < monitors.length; i++) {
            var mon = data.monitors[i];

            if (mon.type == "score") {
                mon.status = "";
            }

            if (currentStatus != mon.status) {

                var rclass = "";
                if (mon.status == "active") {
                    rclass = "table-success";
                }
                else if (mon.status == "testing") {
                    rclass = "table-info";
                }

                var row = $('<tr>').addClass(rclass);
                row.append($('<th>').text(mon.status));
                row.append($('<td>').text("Score").addClass(""));
                table.append(row);
                currentStatus = mon.status;
            }

            var row = $('<tr>').addClass('legend').data('monitor_id', mon.id);

            var name = mon.name;

            var rclass = "table-light";
            if (mon.type == "score") {
                if (mon.name == "recentmedian") {
                    rclass = "table-primary";
                } else {
                    rclass = "table-secondary";
                }
                if (mon.name == "every") {
                    name = "legacy";
                }
                name += " score";
            }
            else {

            }

            row.append($('<td>').text(name).addClass(rclass));
            row.append($('<td>').text(mon.score));
            // row.append($('<td>').text(mon.status));
            // row.append($('<td>').text(mon.type).addClass('legend').data('monitor_id', mon.id));

            table.append(row);
        }

        var fadeout = fade(0.25);
        var fadein  = fade(1);
        table.find('tr').mouseenter(function(e) {

            var mon = $(this).data('monitor_id');
            if (!mon) { return; }
            fadeout( { monitor_id: mon } );
        });
        table.find('tr').mouseleave(function(e) {
            var mon = $(this).data('monitor_id');
            if (!mon) { return; }
            fadein( { monitor_id: mon } );
        });

        legend.append(table);
    }

    function fade (opacity) {
        return function(g, i) {
            svg.selectAll(".monitor_data")
               .filter(function(d) {
                   return d.monitor_id !== g.monitor_id;
               })
            .transition()
            .style("opacity", opacity);
        };
    };

}
