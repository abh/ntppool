if (!NP) var NP = {};

  NP.netspeed_updated = function(server_id, data, status) {
          $('#netspeed_' + server_id ).fadeIn(400);
          $('#netspeed_' + server_id ).html(data.netspeed);
          $('#zones_' + server_id ).html(data.zones);
  };

  NP.update_netspeed = function(server_id, netspeed) {

     var pars = { "netspeed": netspeed, "server": server_id };

     $('#netspeed_' + server_id ).fadeOut(50);

     jQuery.getJSON( '/manage/server/update/netspeed', pars,
                     function(data, textStatus) {
                         NP.netspeed_updated(server_id, data)
                     }
                    );
  };


$(document).ready(function () {

  $("#busy")
    .ajaxStart(function(){
        $(this).show(70);
    })
    .ajaxStop(function(){
        $(this).hide(70);
    });

  $("#profile_link a.profile_link_change")
     .live('click',
           function(event) {
               event.preventDefault();
               $.post(this.href, {},
                      function(response) {
                          $('#profile_link').html(response);
                      })
           }
          );
});
