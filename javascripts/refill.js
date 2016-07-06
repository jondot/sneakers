$(document).ready(function () {


  $('pre code').each(function(i, block) {
    hljs.highlightBlock(block);
  });
  console.log("highlight loaded");

  var menu = $('#navigation-menu');
  var menuToggle = $('#js-mobile-menu');

  $(menuToggle).on('click', function(e) {
    e.preventDefault();
    menu.slideToggle(function(){
      if(menu.is(':hidden')) {
        menu.removeAttr('style');
      }
    });
  });
  
});
