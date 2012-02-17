
function update_graph(div, data) {

    $.each(data, function(i,d) {
        d.date = new Date(d.ts * 1000);
    });

    var y_offset_max = d3.max(data.map(function(e){ return e.offset * 1 })),
        y_offset_min = d3.min(data.map(function(e){ return e.offset * 1 }));

    // more than 4 seconds off and it's a little crazy anyway, I think...
    if (y_offset_max >  4) { y_offset_max =  4 }
    if (y_offset_min < -4) { y_offset_min = -4 }

    $(".graph_desc").show();

    var w = 480,
        h = 200,
        pad_w = 35,
        pad_h = 15,

        y_offset = d3.scale.pow().exponent(0.7).domain([y_offset_max, y_offset_min]).range([0, h]).clamp(true),

        y_score = d3.scale.sqrt().domain([25,-105]).range([0,h]),

        x = d3.time.scale.utc().domain([d3.min(data.map(function(e){ return e.date })),
                                        d3.max(data.map(function(e){ return e.date }))
            ])
            .range([0, w]);

    var vis = d3.select(div)
        .append("svg:svg")
        .attr("width", w + pad_w * 2)
        .attr("height", h + pad_h * 2)
        .append("g")
        .attr("transform", "translate(" + pad_w + "," + pad_h + ")");

    var xrule = vis.selectAll("g.x")
        .data(x.ticks(10))
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
    var yrule = vis.selectAll("g.y")
        .data(y_offset.ticks(7))
        .enter().append("g")
        .attr("class", "y");

    yrule.append("line")
        .attr("x1", 0)
        .attr("x2", w)
        .attr("y1", y_offset)
        .attr("y2", y_offset);

    yrule.append("text")
        .attr("x", -3)
        .attr("y", y_offset)
        .attr("dy", ".35em")
        .attr("text-anchor", "end")
        .text(function(ms) {ms = ms * 1000;
                            return y_offset.tickFormat(0)(ms);
        });

/* score y lines */
var yrule_score = vis.selectAll("g.y_scores")
    .data([20,0,-20,-50,-100])
    .enter().append("g")
    .attr("class", "y_score");

yrule_score.append("line")
    .attr("x1", 0)
    .attr("x2", w)
    .attr("y1", y_score)
    .attr("y2", y_score);

yrule_score.append("text")
    .attr("x", w + 23)
    .attr("y", y_score)
    .attr("dy", ".35em")
    .attr("text-anchor", "end")
    .text(function(text) { return text });


var zero_offset = vis.selectAll("g.zero_offset")
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

vis.append("rect")
    .attr("width", w)
    .attr("height", h);

vis.selectAll("g.scores")
    .data(data)
    .enter().append("circle")
    .attr("class", "scores")
    .attr("r", 2)
    .attr("transform", function(d,i) { var tr = "translate(" + x(d.date) + "," + y_score(d.score) + ")"; return tr })
    .style("fill", function(d) {
        if (d.step < -1) {
           return "red";
        }
        else if (d.step < 0) {
           return "orange";
        }
        else {
           return "steelblue";
        }
});

vis.selectAll("g.offsets")
    .data(data)
    .enter().append("circle")
    .attr("class", "offsets")
    .attr("r", 1.5) // todo: make this 2 if number of data points are < 250 or some such
    .attr("transform", function(d,i) { return "translate(" + x(d.date) + "," + y_offset(d.offset) + ")"; })
    .style("fill", function(d) {
        var offset = d.offset;

        if (offset < 0) { offset = offset * -1 }
        if ( offset < 0.050 ) {
            return "green";
        }
        else if ( offset < 0.100 ) {
            return "orange";
        }
        else {
            return "red";
       }
 });

}

$(document).ready(function(){

   var graph_div = $('#graph');

   if (!Modernizr.svg) { // no svg support, show the noscript section
       var $legacy = $('#legacy-graphs');

       $legacy.html('Please upgrade to a browser that supports SVG '
                    + 'to see the new graphs. '
                    + '(For example <a href="http://www.apple.com/safari/">Safari</a>, '
                    + '<a href="https://www.google.com/chrome/">Chrome</a>, '
                    + '<a href="http://www.mozilla.org/firefox">Firefox</a> or '
                    + '<a href="http://ie.microsoft.com/">IE9+</a>)<br>'
                   );

       $legacy.append($('<br><img class=".legacy-graph-img"/>')
           .attr('src', $legacy.data('score-graph-url')));
       $legacy.append($('<br><img class=".legacy-graph-img"/>')
           .attr('src', $legacy.data('offset-graph-url')));

       return;
   }

   var ip = graph_div.data('server-ip');
   if (!ip) { return }

   var data;

   d3.json("/scores/"+ ip +"/json?monitor=1&limit=200", function(json) {
      data = json.history;
      update_graph('#graph', data);
   });


});

