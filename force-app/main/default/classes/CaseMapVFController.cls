public with sharing class CaseMapVFController {

    public String casesJson { get; private set; }

    public CaseMapVFController() {
        List<CaseMapController.CaseMapRecord> records = CaseMapController.getOpenCases();
        casesJson = JSON.serialize(records);
    }
}