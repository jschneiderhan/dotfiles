import { module, test } from 'qunit';
import { setupRenderingTest } from 'ember-qunit';
import { render } from '@ember/test-helpers';
import hbs from 'htmlbars-inline-precompile';

module('Integration | Component | rental-listing', function(hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function() {
    this.rental = EmberObject.create({
      image: 'fake.png',
      
    });
  });

  test('should display rental details', async function(assert) {

  });

  test('should toggle wide class on click', async function(assert) {

  });
});
