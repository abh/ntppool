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
            zone_list.editable('/api/staff/server_zones', {
                submit_data: {
                    auth_token: NP.token,
                    server: zone_list.data('server-ip')
                },
                data: zone_list.data('zones'),
                indicator: 'Saving...',
                cancel: 'Cancel',
                submit: 'Save',
                callback: function(zones,editable) {
                    console.log(zones);
                    return "bah!";
                }
            });
       
            $('#server_edit_zones').click(function() {
                console.log("button click");
                zone_list.click();
                $('#server_edit_zones').hide();
            });
        }
    });
})(jQuery);
