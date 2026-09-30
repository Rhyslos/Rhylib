-- Server setting, sent to every client. 0 forces first person for everyone.
CreateConVar("rhylib_thirdperson_allowed", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Allow Rhylib over-the-shoulder third person (0/1)")
