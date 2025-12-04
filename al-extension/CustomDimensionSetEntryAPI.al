page 50103 "Custom Dimension Set Entry API"
{
    APIGroup = 'qrReader';
    APIPublisher = 'davidb';
    APIVersion = 'v1.0';
    EntityName = 'dimensionSetEntry';
    EntitySetName = 'dimensionSetEntries';
    PageType = API;
    SourceTable = "Dimension Set Entry";
    Editable = false;
    ODataKeyFields = "Dimension Set ID", "Dimension Code";

    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                field(dimensionSetId; Rec."Dimension Set ID")
                {
                    Caption = 'Dimension Set ID';
                }
                field(dimensionCode; Rec."Dimension Code")
                {
                    Caption = 'Dimension Code';
                }
                field(dimensionValueCode; Rec."Dimension Value Code")
                {
                    Caption = 'Dimension Value Code';
                }
                field(dimensionValueName; Rec."Dimension Value Name")
                {
                    Caption = 'Dimension Value Name';
                }
            }
        }
    }
}
