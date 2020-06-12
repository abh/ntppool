/* Copyright 2006-2013 Ask Bjørn Hansen, Develooper LLC */
/*jshint jquery:true browser:true */

if (!NP) var NP = {};

(function () {

    "use strict";

    NP.netspeed_updated = function (server_id, data) {
        $('#netspeed_' + server_id).fadeIn(400);
        $('#netspeed_' + server_id).html(data.netspeed);
        $('#zones_' + server_id).html(data.zones);
    };

    NP.update_netspeed = function (server_id, netspeed, auth_token) {
        var pars = { "netspeed": netspeed, "server": server_id, "auth_token": auth_token };
        $('#netspeed_' + server_id).fadeOut(50);
        jQuery.getJSON('/manage/server/update/netspeed', pars,
            function (data, textStatus) {
                NP.netspeed_updated(server_id, data);
            }
        );
    };

    NP.recheck_mode7 = function (server_id) {
        console.log("recheck mode7");
        var span = $('#mode7check_' + server_id);
        var pars = { "server": server_id };
        span.fadeOut(50);
        jQuery.getJSON('/manage/server/update/mode7check', pars,
            function (data, textStatus) {
                span.fadeIn(100);
                span.html("Check has been scheduled<br>");
            }
        );
    };

    $(document).ready(function () {
        $("#busy").ajaxStart(function () {
            $(this).show(70);
        })
            .ajaxStop(function () {
                $(this).hide(70);
            });
    });

    // check that it compiles?
    createCheckoutSession(false);

    checkoutButtons.forEach(function(b) {

        b.addEventListener('click', function () {

            var parameters = {};

            console.log("got checkout button!");

            createCheckoutSession(parameters).then(function (response) {

                stripe.redirectToCheckout({
                    sessionId: response.checkoutSessionId
                }).then(function (result) {
                    // If `redirectToCheckout` fails due to a browser or network
                    // error, display the localized error message to your customer
                    // using `result.error.message`.
                });
            });
        })
    })
}());


(function () {
    var stripe = Stripe('pk_test_Gs3tmJLpNZmmxbpIpqFcBE1H');

    var checkoutButtons = document.querySelectorAll('.checkout-button');

    if (checkoutButtons.length == 0) {
        return;
    }

    var createCheckoutSession = function (params) {
        return fetch("/manage/vendor/plan/create_session", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify(params),
        }).then(function (response) {
            return response.json();
        });
    };

    // check that it compiles?
    createCheckoutSession(false);

    checkoutButtons.forEach(function(b) {

        b.addEventListener('click', function () {

            var parameters = {};

            console.log("got checkout button!");

            createCheckoutSession(parameters).then(function (response) {

                stripe.redirectToCheckout({
                    sessionId: response.checkoutSessionId
                }).then(function (result) {
                    // If `redirectToCheckout` fails due to a browser or network
                    // error, display the localized error message to your customer
                    // using `result.error.message`.
                });
            });
        })
    })
}());
