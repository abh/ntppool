/* Copyright 2012 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */
/*global _:true, templates:true */

if(!1 in window)window.console={log:function(){}};
else if(!console)var console={log:function(){}};

if (!NP) { var NP = {}; }

(function ($) {
    "use strict";
    $(document).ready(function() {
        $('#search_form').submit(function(e) {
            e.preventDefault();
            var q = $(this).find('input:first').val();
            $('#users').html("Loading ...");
            $.post('/api/staff/search',
                    { q: q },
                    function(r) {
                        var reg = new RegExp(q, 'gi');
                        _.each(r.users, function(user) {
                            _.each(user.servers, function(server) {
                                server.ip_display = server.ip;
                                server.ip_display = server.ip_display.replace(reg,
                                    function(str) {
                                        console.log("STR", str);
                                        return '<b>' + str + '</b>';
                                    }
                                );
                            });
                        });
                        $('#users').html( templates.users.render( r ));
                    }, 'json'
            );
        });

        var zone_list = $('#zone_list');

        if (zone_list) {
            zone_list.editable('/api/staff/edit_server', {
                submitdata: {
                    auth_token: NP.token,
                    server: zone_list.data('server-ip')
                },
                data: function() { return zone_list.data('zones') },
                indicator: 'Saving...',
                event: "dblclick",
                select: false,
                cancel: 'Cancel',
                submit: 'Save',
                callback: function(zones, editable) {
                    var zones_data = JSON.parse(zones),
                        zones_str = zones_data.join(" ");
                    zone_list.data('zones', zones_str);
                    $('#zone_list').html(zones_str);
                    $('#server_edit_zones').show();

                }
            });

            $('#server_edit_zones').click(function() {
                console.log("button click");
                zone_list.dblclick();
                $('#server_edit_zones').hide();
            });
        }
    });
})(jQuery);
