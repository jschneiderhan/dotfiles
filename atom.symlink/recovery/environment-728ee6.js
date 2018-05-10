'use strict';

module.exports = function(environment) {
  const ENV = {
    modulePrefix: 'snap',
    environment,
    rootURL: '/',
    routerRootURL: environment === "beta" ? "/beta" : "/",

    // ember-router-scroll
    locationType: 'router-scroll',
    historySupportMiddleware: true,

    EmberENV: {
      FEATURES: {
        // Here you can enable experimental features on an ember canary build
        // e.g. 'with-controller': true
        'ds-improved-ajax': true,
        'ds-rollback-attribute': true
      },
      EXTEND_PROTOTYPES: {
        // Prevent Ember Data from overriding Date.parse.
        Date: false
      }
    },

    newRelic: {
      licenseKey: '96395fa1d4',
      spaMonitoring: true
    },

    APP: {
      // Here you can pass flags/options to your application instance
      // when it is created
      signInPath: '/session/sign_in',
      signOutPath: '/session/sign_out',
      enrollIframePath: '/enroll/new',

      versionCheck: {
        minutesBetween: environment === "test" ? 120 : 1,
        URL: environment === "beta" ? "/beta/latest_deploy" : "/latest_deploy"
      },

      adp: {
        connectorAppListingURL: 'https://apps.adp.com/apps/185602',
        consentRequestURL: 'https://adpapps.adp.com/consent-manager/pending/direct?consumerApplicationID=9389e144-5461-4d11-9741-b09b9d1dfc79&successUri=',
        consentRequestCallbackURL: 'http://snap.myhdev.com:3700/webhooks/adp/consent_validation?adp_purchase_id='
      },

      signupTrialLengthInDays: 30,
      signup: false
    }
  };

  ENV.moment = {
    includeTimezone: 'all'
  };

  // tell Semantic UI not to use `bower_components/`` as the source folder
  ENV.SemanticUI = {
    source: {
      css: 'node_modules/semantic-ui/dist',
      javascript: 'node_modules/semantic-ui/dist',
      images: 'node_modules/semantic-ui/dist/themes/default/assets/images',
      fonts: 'node_modules/semantic-ui/dist/themes/default/assets/fonts'
    }
  };

  ENV.stripe = {
    lazyLoad: true,
    publishableKey: 'pk_test_TQHoMvgFKSLsfa1SOESPUqSG'
  };

  // This config is required even for environments that aren't using it,
  // to avoid an error.
  ENV.hotjar = {
    id: "__dummy__", // dummy value since this must be truthy
    enabled: false
  };

  if (environment === 'development') {
    // Change to true if you want to use fixture data from Mirage
    ENV['ember-cli-mirage'] = { enabled: false };

    // ENV.APP.LOG_RESOLVER = true;
    // ENV.APP.LOG_ACTIVE_GENERATION = true;
    // ENV.APP.LOG_TRANSITIONS = true;
    // ENV.APP.LOG_TRANSITIONS_INTERNAL = true;
    // ENV.APP.LOG_VIEW_LOOKUPS = true;
    ENV.APP.accountUrl = "http://account.myhdev.com:3400";
    ENV.APP.goDomain = "go.myhdev.com:3400";
    ENV.APP.goUrl = "http://go.myhdev.com:3400";
    ENV.APP.googleClientId = "574296776985-6pm1q51ff2j1mlg5hqguibb6jmcgare7.apps.googleusercontent.com";
    ENV.APP.googleTagManager = {
      enabled: false
    };
    ENV.APP.signup = true;
  }

  if (environment === 'test') {
    // Testem prefers this...
    ENV.locationType = 'none';

    // keep test console output quieter
    ENV.APP.LOG_ACTIVE_GENERATION = false;
    ENV.APP.LOG_VIEW_LOOKUPS = false;

    ENV.APP.rootElement = '#ember-testing';
    ENV.APP.autoboot = false;
    ENV.APP.accountUrl = "http://account.myhdev.com:3400";
    ENV.APP.goDomain = "go.myhdev.com:3400";
    ENV.APP.goUrl = "http://go.myhdev.com:3400";
    ENV.APP.googleClientId = "fake-client-id123.apps.googleusercontent.com";
    ENV.APP.googleTagManager = {
      enabled: false
    };
    ENV.APP.signup = true;
    ENV.stripe.mock = true;
  }

  if (environment === 'production') {
    // here you can enable a production-specific feature
    ENV.APP.accountUrl = "https://account.meyouhealth.com";
    ENV.APP.goDomain = "go.meyouhealth.com";
    ENV.APP.goUrl = "https://go.meyouhealth.com";
    ENV.newRelic.applicationId = '21523134';
    ENV.APP.googleClientId = "610258323492-5oqgbs8e7hs6cb5jgsjpkbsvl0tsioub.apps.googleusercontent.com";
    ENV.APP.googleTagManager = {
      enabled: true,
      dataLayer: {
        'environment': 'production'
      }
    };
    ENV.stripe.publishableKey = 'pk_test_TQHoMvgFKSLsfa1SOESPUqSG'; // TODO

    ENV.hotjar = {
      id: "807548",
      enabled: true
    };
  }

  if (environment === 'beta') {
    ENV.APP.accountUrl = "https://account.meyouhealth.com";
    ENV.APP.goDomain = "go.meyouhealth.com";
    ENV.APP.goUrl = "https://go.meyouhealth.com";
    ENV.newRelic.applicationId = '117415583';
    ENV.APP.googleClientId = "610258323492-5oqgbs8e7hs6cb5jgsjpkbsvl0tsioub.apps.googleusercontent.com";
    ENV.APP.googleTagManager = {
      enabled: true,
      dataLayer: {
        'environment': 'beta'
      }
    };
    ENV.stripe.publishableKey = 'pk_test_TQHoMvgFKSLsfa1SOESPUqSG'; // TODO
  }

  if (environment === 'staging') {
    // here you can enable a staging-specific feature
    ENV.APP.accountUrl = "https://account.myhstg.com";
    ENV.APP.goDomain = "go.myhstg.com";
    ENV.APP.goUrl = "https://go.myhstg.com";
    ENV.newRelic.applicationId = '118021734';
    ENV.APP.googleClientId = "384529221566-5kgff911u2bdt40m4e00otkc1hkq5b7d.apps.googleusercontent.com";
    ENV.APP.googleTagManager = {
      enabled: false
    };
    ENV.stripe.publishableKey = 'pk_test_TQHoMvgFKSLsfa1SOESPUqSG'; // TODO

    ENV.hotjar = {
      id: "807646",
      enabled: true
    };
    ENV.APP.signup = true;
  }

  return ENV;
};
