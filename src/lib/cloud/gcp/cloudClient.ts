/**
 * Copyright 2020 F5 Networks, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


'use strict';

import {google, GoogleApis} from 'googleapis';
import * as constants from '../../../constants'
import { AbstractCloudClient } from '../abstract/cloudClient'
import * as utils from "../../utils";

/* eslint-disable  @typescript-eslint/no-explicit-any */
export class GcpCloudClient extends AbstractCloudClient {
    secretmanager: any;
    google: GoogleApis;
    projectId: string;
    authToken: any;
    constructor(options?: any) {
        const secretmanager = google.secretmanager('v1');
        super(constants.CLOUDS.GCP, options);
        this.google = google;
        this.secretmanager = secretmanager;
    }

    /**
     * See the parent class method for details
     */
    init(): Promise<void> {
        return this._getProjectId()
            .then((result) => {
                this.projectId = result;
                return this._getAuthToken();
            })
            .then((result) => {
                this.authToken = result;
                return Promise.resolve();
            })
            .catch(err => Promise.reject(err))
    }


    /**
     * Gets secret from GCP Secrets Manager
     *
     * @param secretId                      - secret name
     * @param [options]                     - cloud specific metadata for getting secret value
     * @param [options.version]             - version value for secret
     *
     * @returns
     */
    getSecret(secretId: string, options?: {
        version?: string;
    }): Promise<string> {
        if (!secretId) {
            throw new Error('GCP Cloud Client secret id is missing');
        }
        const version = (options ? options.version : undefined) || 'latest';
        const params = {
            auth: this.authToken,
            name: `projects/${this.projectId}/secrets/${secretId}/versions/${version}`
        };
        return this.secretmanager.projects.secrets.versions.access(params)
            .then((response) => {
                const buff = Buffer.from(response.data.payload.data, 'base64');
                const secret = buff.toString('ascii');
                return Promise.resolve(secret);
            })
            .catch((err) => {
                const message = `Error getting secret from ${secretId} ${err.message}`;
                return Promise.reject(new Error(message));
            });
    }

    /**
     * Returns cloud name
     *
     * @returns {String}
     */
    getCloudName(): string {
        return constants.CLOUDS.GCP;
    }

    /**
     * Returns accountId/subscriptionId from Azure
     *
     * @returns {String}
     */
    getCustomerId(): string {
        return this.projectId;
    }

    /**
     * Gets value from Google metadata
     *
     * @param field                         - metadata property to fetch
     * @param [options]                     - function options
     *
     * @returns {Promise}
     */
    async getMetadata(field: string, options?: {
        type?: string;
        index?: number;
    }): Promise<string> {
        const type = options ? options.type : undefined;
        const index = options ? options.index : undefined;

        if (!field) {
            throw new Error('Google Cloud Client metadata field is missing');
        }

        if (!type) {
            throw new Error('Google Cloud Client metadata type is missing');
        }


        if (type != 'compute' && type != 'network') {
            throw new Error('Google Cloud Client metadata type is unknown. Must be one of [ compute, network ]');
        }

        if (type === 'network' && index === undefined) {
            throw new Error('Google Cloud Client network metadata index is missing');
        }

        let result: string;

        if (type == 'compute') {
            const response = await utils.makeRequest(
                `http://metadata.google.internal/computeMetadata/v1/instance/${field}`,
                {
                    method: 'GET',
                    headers: {
                        'Metadata-Flavor': 'Google'
                    }
                }
            );

            result = response.body.replace(/_/g, '-');
        } else if(type === 'network') {
            const responseIp = await utils.makeRequest(
                `http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/${index}/${field}`,
                {
                    method: 'GET',
                    headers: {
                        'Metadata-Flavor': 'Google'
                    }
                }
            );

            const responseMask = await utils.makeRequest(
                `http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/${index}/subnetmask`,
                {
                    method: 'GET',
                    headers: {
                        'Metadata-Flavor': 'Google'
                    }
                }
            );

            const maskNodes = responseMask.body.match(/(\d+)/g);
            let cidr = 0;
            for(const i in maskNodes) {
                cidr += (((maskNodes[i] >>> 0).toString(2)).match(/1/g) || []).length;
            }
            result = `${responseIp.body}/${cidr}`;
        }
        return result;
    }

    /**
     * Get projectId
     *
     * @returns {Promise} A promise which is resolved with the projectId requested
     *
     */
    _getProjectId(): Promise<string> {
        return this.google.auth.getProjectId()
            .then((projectId) => Promise.resolve(projectId)) /* eslint-disable-line */
            .catch((err) => {
                const message = `Error getting project id ${err.message}`;
                return Promise.reject(new Error(message));
            });
    }

    /**
     * Get bearer auth token
     *
     * @returns {Promise} A promise which is resolved with bearer auth token
     *
     */

    _getAuthToken(): Promise<any> {
        return this.google.auth.getClient({
            scopes: [
                'https://www.googleapis.com/auth/cloud-platform',
                'https://www.googleapis.com/auth/secretmanager'
            ]
        })
            .then((authToken) => Promise.resolve(authToken)) /* eslint-disable-line */
            .catch((err) => {
                const message = `Error getting auth token ${err.message}`;
                return Promise.reject(new Error(message));
            });
    }
}

