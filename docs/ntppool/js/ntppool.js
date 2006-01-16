
  function update_netspeed(server_id, netspeed) {
//     Object.dpDump(server_id);
//     Object.dpDump(netspeed);
     var pars = 'netspeed=' + netspeed + '&server=' + server_id;
     new Ajax.Updater( 'netspeed_' + server_id,  '/manage/update/netspeed', { parameters: pars,asynchronous: 1 });
  }

Ajax.Responders.register({
  onCreate: function() {
    if($('busy') && Ajax.activeRequestCount>0) {
      Effect.Appear('busy',{duration:0.5,queue:'end'});
    }
  },
  onComplete: function() {
    if($('busy') && Ajax.activeRequestCount===0) {
      Effect.Fade('busy',{duration:0.5,queue:'end'});
    }
  }
});

