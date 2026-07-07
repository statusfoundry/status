import Testing
@testable import StatusCore

@Test func changedToMatchesFirstObservationWhenCurrentValueMatchesTarget() {
    let condition = MappingCondition(
        path: "$.attributes.appStoreState",
        operation: .changedTo,
        value: "REJECTED"
    )

    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "REJECTED"],
        previousState: nil
    ))
}

@Test func changedToDoesNotMatchRepeatedObservation() {
    let condition = MappingCondition(
        path: "$.attributes.appStoreState",
        operation: .changedTo,
        value: "REJECTED"
    )

    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "REJECTED"],
        previousState: ["appStoreState": "REJECTED"]
    ) == false)
}

@Test func changedToMatchesTransitionIntoTargetState() {
    let condition = MappingCondition(
        path: "$.attributes.appStoreState",
        operation: .changedTo,
        value: "REJECTED"
    )

    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "REJECTED"],
        previousState: ["appStoreState": "IN_REVIEW"]
    ))
}

@Test func changedFromMatchesTransitionOutOfTargetState() {
    let condition = MappingCondition(
        path: "$.attributes.appStoreState",
        operation: .changedFrom,
        value: "REJECTED"
    )

    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "WAITING_FOR_REVIEW"],
        previousState: ["appStoreState": "REJECTED"]
    ))
}

@Test func changedDoesNotMatchFirstObservationButMatchesDifferentPriorValue() {
    let condition = MappingCondition(path: "$.attributes.appStoreState", operation: .changed)

    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "REJECTED"],
        previousState: nil
    ) == false)
    #expect(MappingConditionEvaluator.evaluate(
        condition,
        currentState: ["appStoreState": "REJECTED"],
        previousState: ["appStoreState": "IN_REVIEW"]
    ))
}

@Test func plainMappingConditionsUseCurrentStateOnly() {
    #expect(MappingConditionEvaluator.evaluate(
        MappingCondition(path: "$.workflow.conclusion", operation: .equals, value: "failure"),
        currentState: ["conclusion": "failure"],
        previousState: ["conclusion": "success"]
    ))
    #expect(MappingConditionEvaluator.evaluate(
        MappingCondition(path: "$.metrics.views", operation: .greaterThan, value: "100"),
        currentState: ["views": "250"],
        previousState: nil
    ))
    #expect(MappingConditionEvaluator.evaluate(
        MappingCondition(path: "$['display name']", operation: .contains, value: "status"),
        currentState: ["display name": "Status Foundry"],
        previousState: nil
    ))
}
