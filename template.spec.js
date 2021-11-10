/// <reference types="Cypress" />
import * as user from "../../../fixtures/Users.json";
import * as workflows from "../../../fixtures/Workflows.json";

describe("Testing the workflow creation wizard using Templates", () => {
  before("Clearing the Cookies and deleting the Cookies", () => {
    cy.requestLogin(user.AdminName, user.AdminPassword);
    cy.waitForCluster("Self-Agent");
    cy.visit("/create-workflow");
  });

  let workflowName = "";
  let workflowNamespace = "";
  let workflowSubject = "";

  it("Scheduling a workflow without target application", () => {
    cy.chooseAgent("Self-Agent");
    cy.get("[data-cy=ControlButtons] Button").eq(0).click();
    cy.chooseWorkflow(2, 0);

    cy.get("[data-cy=WorkflowNamespace] input").then(($namespace) => {
      cy.wrap($namespace.val()).as("workflowNamespace");
      workflowNamespace = $namespace.val();
      return;
    });

    // Provide the correct details
    cy.configureWorkflowSettings(
      workflows.customWorkflow,
      workflows.customWorkflowDescription,
      0
    );
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    // Expected nodes
    const graphNodeNameArray = ["install-chaos-experiments"];
    // Verify nodes in dagre graph
    cy.validateGraphNodes(graphNodeNameArray);
    /***
     * Add an experiment containing pod text
     */
    cy.get("[data-cy=addExperimentButton]").should("be.visible");
    cy.get("[data-cy=addExperimentButton]").click();
    /**
     * Waiting for the search experiment field to be visible
     */
    cy.get("[data-cy=addExperimentSearch]").should("be.visible");
    cy.get("[data-cy=addExperimentSearch]")
      .find("input")
      .clear()
      .type("cassandra-pod-delete");
    cy.get("[data-cy=ExperimentList] :radio").eq(0).check();
    cy.get("[data-cy=AddExperimentDoneButton]").click();
    /**
     * Waiting for the dagre animation to complete after closing the
     * add experiment modal
     */
    cy.wait(1000);
    cy.get("table")
      .find("tr")
      .eq(1)
      .then(($div) => {
        cy.wrap($div)
          .find("td")
          .eq(0)
          .should("contain.text", "cassandra-pod-delete") // Matching Experiment
          .click();
      });
    cy.wait(1000);
    const tunningParameters = {
      general: {
        hubName: "Litmus ChaosHub",
        experimentName: "pod-delete",
        context: "pod-delete_litmus",
      },
      targetApp: {
        annotationCheckToggle: false,
        appns: "default",
        appKind: "deployment",
        appLabel: "app=nginx",
      },
      steadyState: {},
      tuneExperiment: {
        totalChaosDuration: 30,
        chaosInterval: 10,
        force: "false",
      },
    };
    cy.tuneCustomWorkflow(tunningParameters);
    // Expected nodes
    const graphNodesNameArray = [
      "install-chaos-experiments",
      "cassandra-pod-delete",
    ];
    // Verify nodes in dagre graph
    cy.validateGraphNodes(graphNodesNameArray);
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.rScoreEditor(5);
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.selectSchedule(0);
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.verifyDetails(
      workflows.customWorkflow,
      workflows.customWorkflowDescription,
      0
    );
    cy.get("@workflowNamespace").then((workflowNamespace) => {
      cy.get("[data-cy=WorkflowSubject]").should(
        "have.text",
        `${workflows.customWorkflow}_${workflowNamespace}`
      );
    });
    cy.get("[data-cy=WorkflowSubject] textarea")
      .eq(0)
      .clear()
      .type("custom-workflow-subject");
    cy.get("[data-cy=ControlButtons] Button").eq(0).click(); // Clicking on finish Button
    cy.get("[data-cy=FinishModal]").should("be.visible");
    cy.get("[data-cy=WorkflowName]").then(($name) => {
      workflowName = $name.text();
      return;
    });
    cy.get("[data-cy=WorkflowSubject]").then(($subject) => {
      workflowSubject = $subject.text();
      return;
    });
    cy.get("[data-cy=GoToWorkflowButton]").click();
  });

  it("Validating workflow existence and status on cluster", () => {
    cy.validateWorkflowExistence(workflowName, workflowNamespace);
    cy.validateWorkflowStatus(workflowName, workflowNamespace, ["Running"]);
  });

  it("Checking Workflow Browsing Table for scheduled workflow", () => {
    cy.GraphqlWait("workflowDetails", "listWorkflows");
    cy.visit("/workflows");
    cy.wait("@listWorkflows").its("response.statusCode").should("eq", 200);
    cy.wait(1000);
    cy.get("table")
      .find("tr")
      .eq(1)
      .then(($div) => {
        cy.wrap($div).find("td").eq(1).should("have.text", "Running"); // Matching Status
        cy.wrap($div).find("td").eq(2).should("have.text", workflowName); // Matching Workflow Name Regex
        cy.wrap($div).find("td").eq(3).should("have.text", "Self-Agent"); // Matching Target Agent
        // cy.wrap($div).find("td [data-cy=browseWorkflowOptions]").click(); // Clicking on 3 Dots
        // cy.get("[data-cy=workflowDetails]").eq(0).click(); // Checking Workflow Graph And Other Details
      });
  });

  it("Saving the created workflow as a template", () => {
    cy.GraphqlWait("workflowListDetails", "listSchedules");
    cy.GraphqlWait("addWorkflowTemplate", "addTemplate");
    cy.get("[data-cy=browseSchedule]").click();
    cy.wait("@listSchedules").its("response.statusCode").should("eq", 200);
    cy.wait(1000);
    cy.get("table")
      .find("tr")
      .eq(1)
      .then(($div) => {
        cy.wrap($div).find("td").eq(0).should("have.text", workflowName); // Matching Workflow Name Regex
        cy.wrap($div).find("td").eq(1).should("have.text", "Self-Agent"); // Matching Target Agent
      });
    cy.get("[data-cy=browseScheduleOptions]")
      .eq(0)
      .click({ scrollBehavior: false });
    cy.get("[data-cy=saveTemplate]")
      .eq(0)
      .should("have.text", "Save Template")
      .click({ force: true });
    cy.configureWorkflowSettings(
      "e2e-test-template",
      "e2e-test-template-description",
      0
    );
    cy.get("[data-cy=saveTemplateButton]").should("be.visible").click();
    cy.wait("@addTemplate").its("response.statusCode").should("eq", 200);
    cy.get("[data-cy=templateAlert]").should("be.visible");
    cy.wait(6000);
  });

  it("Scheduling a new workflow from the saved template", () => {
    cy.visit("/create-workflow");
    cy.chooseAgent("Self-Agent");
    cy.get("[data-cy=ControlButtons] Button").eq(0).click();
    cy.chooseWorkflow(1, 0);
    cy.configureWorkflowSettings(
      "test-schedule-template",
      workflows.nonRecurringworkflowDescription,
      0
    );
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.wait(1000); // Needs to be removed with frontend enhancement
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.rScoreEditor(5);
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.selectSchedule(0);
    cy.get("[data-cy=ControlButtons] Button").eq(1).click();
    cy.verifyDetails(
      "test-schedule-template",
      workflows.nonRecurringworkflowDescription,
      0
    );
    cy.get("[data-cy=ControlButtons] Button").eq(0).click(); // Clicking on finish Button
    cy.get("[data-cy=FinishModal]").should("be.visible");
    cy.get("[data-cy=GoToWorkflowButton]").click();
  });
});
