'use strict';

const path = require('path');
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');

const PROTO_PATH = path.join(__dirname, '..', '..', 'api', 'proto', 'recommendations.proto');

const packageDefinition = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: Number,
  enums: String,
  defaults: true,
  oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDefinition);
const RecommendationsService = proto.funwithactivity.recommendations.v1.RecommendationsService;

const APP_SERVER_URL = process.env.APP_SERVER_URL || 'localhost:50051';
const INTERNAL_TOKEN = process.env.INTERNAL_GRPC_TOKEN || '';

// Long-lived channel: opened once at module load and reused for every request,
// with keepalive so a reverse-proxied connection does not go idle.
const client = new RecommendationsService(
  APP_SERVER_URL,
  grpc.credentials.createInsecure(),
  {
    'grpc.keepalive_time_ms': 30000,
    'grpc.keepalive_timeout_ms': 5000,
    'grpc.keepalive_permit_without_calls': 1,
    'grpc.max_receive_message_length': 50 * 1024 * 1024,
  },
);

function buildMetadata(requestId) {
  const md = new grpc.Metadata();
  if (INTERNAL_TOKEN) md.set('authorization', 'Bearer ' + INTERNAL_TOKEN);
  if (requestId) md.set('x-request-id', requestId);
  return md;
}

function getRecommendations(payload, requestId) {
  return new Promise((resolve, reject) => {
    const deadline = new Date(Date.now() + 20000);
    client.getRecommendations(payload, buildMetadata(requestId), { deadline }, (err, resp) => {
      if (err) return reject(err);
      resolve(resp || { recommendations: [], statuses: [] });
    });
  });
}

module.exports = { getRecommendations };
