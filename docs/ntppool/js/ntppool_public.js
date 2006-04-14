
function show_graph_explanation() {
  var id = 'graph_explanation';
  var div;
//  if (document.getElementById) {
     div = document.getElementById(id);
//  }
//  else {
//    div = document.all[id];
//     
//  }
  if (div) {
    div.style.display = 'block';  /* or = 'block' */ 
        alert(div.innerHTML);
  }
}