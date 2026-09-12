'use strict';

const { createApp, cosmosStore } = require('./server');

module.exports = createApp({ store: cosmosStore(process.env) }).listen(process.env.PORT || 8080);