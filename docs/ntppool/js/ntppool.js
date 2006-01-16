
  function update_netspeed(server_id, netspeed) {
//     Object.dpDump(server_id);
//     Object.dpDump(netspeed);
     var pars = 'netspeed=' + netspeed + '&server=' + server_id;
     new Ajax.Updater( 'netspeed_' + server_id,  '/manage/update/netspeed', { parameters: pars,asynchronous: 1 });
  }


