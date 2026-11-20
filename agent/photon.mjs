#!/usr/bin/env node
import { PhotonSource } from './photon-source.mjs';
import { runMessageWorker, reportChannelError } from './message-worker.mjs';

runMessageWorker('photon', PhotonSource).catch(reportChannelError);
