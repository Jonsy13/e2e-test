/// <reference types="Cypress" />

// This is an example test script demostrating how kube-api-server
// can be accessed to get details of cluster resources.

import { apis, KUBE_API_TOKEN } from "../kube-apis/apis";

describe("Running Debug Spec for getting status & logs of pods when any failure occurs", () => {
  it("getting pods ---->", () => {
    cy.task("log", "Activating Debugger ---> ");
    cy.request({
      url: apis.getPods("litmus"),
      method: "GET",
      headers: {
        Authorization: `Bearer ${KUBE_API_TOKEN}`,
      },
    }).then((response) => {
      const pods = response.body.items;
      pods.map((pod) => {
        cy.task(
          "log",
          "-----------------------------------------------------------------------------"
        );
        cy.task(
          "log",
          `Pod-Name : ${pod.metadata.name}, ======= Pod_status : ${pod.status.phase}`
        );
        cy.request({
          url: apis.getPodLogs(pod.metadata.name, "litmus"),
          method: "GET",
          headers: {
            Authorization: `Bearer ${KUBE_API_TOKEN}`,
          },
        }).should((logs) => {
          cy.task("log", `logs for ${pod.metadata.name} pod are ------`);
          cy.task("log", logs.body);
          cy.task("log", "\n");
        });
        cy.task(
          "log",
          "------------------------------------------------------------------------------"
        );
      });
    });
    cy.task("log", "Deactivating Debugger");
  });
});
