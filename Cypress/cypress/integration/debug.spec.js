/// <reference types="Cypress" />

// This is an example test script demostrating how kube-api-server
// can be accessed to get details of cluster resources.

import { apis, KUBE_API_TOKEN } from "../kube-apis/apis";
const namespace = "scope";

describe("Running Debug Spec for getting status & logs of pods when any failure occurs", () => {
  const labels = [
    "component=litmusportal-frontend",
    "component=litmusportal-server",
  ];
  it("Getting details of control-plane Pods", () => {
    cy.task("log", "Activating Debugger ---> ");
    labels.map((label) => {
      cy.request({
        url: apis.getPodByLabel(namespace, label),
        method: "GET",
        headers: {
          Authorization: `Bearer ${KUBE_API_TOKEN}`,
        },
      }).then((response) => {
        const pod = response.body.items[0];
        const containers = response.body.items[0].spec.containers;
        console.log(response.body);
        cy.task(
          "log",
          "-----------------------------------------------------------------------------"
        );
        cy.task(
          "log",
          `Pod-Name : ${pod.metadata.name}, ======= Pod_status : ${pod.status.phase}`
        );
        containers.map((container) => {
          cy.request({
            url: apis.getContainerLogs(
              container.name,
              pod.metadata.name,
              namespace
            ),
            method: "GET",
            headers: {
              Authorization: `Bearer ${KUBE_API_TOKEN}`,
            },
          }).should((logs) => {
            cy.task(
              "log",
              `logs for container: ${container.name} in pod: ${pod.metadata.name} ------`
            );
            cy.task("log", logs.body);
          });
          cy.task(
            "log",
            "------------------------------------------------------------------------------"
          );
          cy.task("\n");
        });
      });
      cy.task("log", "Deactivating Debugger");
    });
  });
});
