/// <reference types="Cypress" />

// This is an example test script demostrating how kube-api-server
// can be accessed to get details of cluster resources.

import { apis, KUBE_API_TOKEN } from "../kube-apis/apis";

describe("Running Debug Spec for getting status & logs of pods when any failure occurs", () => {
  it("getting pods ---->",()=> {
    cy.log("Activating Debugger ---> ");
    cy.request({
      url: apis.getPods("kube-system"),
      method: "GET",
      headers: {
        Authorization: `Bearer ${KUBE_API_TOKEN}`,
      },
    }).then((response) => {
      const pods = response.body.items;
      pods.map((pod) => {
        console.log("-----------------------------------------------------------------------------")
        console.log("Pod-Name : ", pod.metadata.name, " =======    Pod_status : ", pod.status.phase);
        cy.request({
          url: apis.getPodlogs(pod.metadata.name,"kube-system"),
          method: "GET",
          headers: {
            Authorization: `Bearer ${KUBE_API_TOKEN}`,
          },
        }).should((logs) => {
          console.log(`logs for ${pod.metadata.name} pod are ------`)
          console.log(logs.body)
          console.log("\n");
        });
        console.log("------------------------------------------------------------------------------")
      });
    });
    cy.log("Deactivating Debugger")
  })
});
