// "SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.4;

contract Verifier {
    function verifyTx(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c, uint[1] memory input
    ) public view returns (bool r) {}
}

contract PrivateVoting {

    struct Voter {
        bool isVerified;
        bool hasVoted;
        uint8 votedCandidateId;
        bool isRegistered;
        bool isBurned;
    }

    struct Candidate {
        string name;
        string motto;
        string photoUrl;
        uint32 voteCount;
    }

    struct Election {
        string name;
        string description;
    }

    enum WorkflowStatus {
        RegisteringElections,
        RegisteringVoters,
        BurnAndRetrieveSessionStarted,
        RegisteringCandidates,
        GeneratingVerifier,
        VerifyingAccounts,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    address public administrator;
    mapping(address => Voter) private voters;
    WorkflowStatus public workflowStatus;
    Candidate[] private candidates;
    Election public election;
    Candidate private winningCandidate;
    mapping(bytes32 => bool) private hashesOfProofs;
    uint128[] private hashesOfSecrets1;
    uint128[] private hashesOfSecrets2;
    Verifier private verifier;

    modifier onlyAdministrator() {
        require(msg.sender == administrator, "the caller of this function must be the administrator");
        _;
    }

    modifier onlyDuringElectionsRegistration() {
        require(workflowStatus == WorkflowStatus.RegisteringElections,
            "this function can be called only during elections registration");
        _;
    }

    modifier onlyDuringVotersRegistration() {
        require(workflowStatus == WorkflowStatus.RegisteringVoters,
            "this function can be called only before proposals registration has started");
        _;
    }

    modifier onlyDuringBaRSession() {
        require(workflowStatus == WorkflowStatus.BurnAndRetrieveSessionStarted,
            "this function can be called only during secrets retrieving");
        _;
    }

    modifier onlyDuringCandidatesRegistration() {
        require(workflowStatus == WorkflowStatus.RegisteringCandidates,
            "this function can be called only during candidates registration");
        _;
    }

    modifier onlyDuringVerifierGeneration() {
        require(workflowStatus == WorkflowStatus.GeneratingVerifier,
            "this function can be called only during verifier generation");
        _;
    }

    modifier onlyDuringVerificationSession() {
        require(workflowStatus == WorkflowStatus.VerifyingAccounts,
            "this function can be called only during verification session");
        _;
    }

    modifier onlyDuringVotingSession() {
        require(workflowStatus == WorkflowStatus.VotingSessionStarted,
            "this function can be called only during the voting session");
        _;
    }

    modifier onlyAfterVotesTallied() {
        require(workflowStatus == WorkflowStatus.VotesTallied,
            "this function can be called only after votes have been tallied");
        _;
    }

    // EVENTS
    // VOTER EVENTS
    event AccountBurnedEvent();

    event VoterVerifiedEvent(address voterAddress);

    event IncorrectSecretPhraseEvent();

    event VotedEvent(address voter, uint candidateId);

    // ADMIN EVENTS
    event ElectionsRegisteredEvent();

    event VoterRegisteredEvent (address voterAddress);

    event CandidateRegisteredEvent(uint candidateId);

    event VerifierConnectedEvent(address verifierAddress);

    event VotesTalliedEvent();

    event WorkflowStatusChangeEvent(WorkflowStatus previousStatus, WorkflowStatus newStatus);

    constructor() {
        administrator = msg.sender;
        workflowStatus = WorkflowStatus.RegisteringElections;
    }

    // VOTER FUNCTIONS
    function burnAndRetrieve(uint128 _secretHash1, uint128 _secretHash2)
    public onlyDuringBaRSession {
        require(voters[msg.sender].isRegistered,
            "the caller of this function must be a registered voter");
        require(!voters[msg.sender].isBurned,
            "the caller is already burned its account");

        voters[msg.sender].isBurned = true;
        hashesOfSecrets1.push(_secretHash1);
        hashesOfSecrets2.push(_secretHash2);

        emit AccountBurnedEvent();
    }

    function verifyAccount(uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[1] memory input)
    public onlyDuringVerificationSession {
        require(input[0] == uint(0x0000000000000000000000000000000000000000000000000000000000000001),
            "the secret phrase is incorrect");
        require(verifier.verifyTx(a, b, c, input), "the generated proof is incorrect");

        bytes32 hashOfProof = keccak256(abi.encodePacked(a, b[0], b[1], c, input));
        require(!hashesOfProofs[hashOfProof], 'this secret phrase has already been used');

        hashesOfProofs[hashOfProof] = true;
        voters[msg.sender].isVerified = true;
        emit VoterVerifiedEvent(msg.sender);
    }

    function vote(uint8 _candidateId)
    public onlyDuringVotingSession {
        require(voters[msg.sender].isVerified, "the caller of this function must be a verified voter");
        require(!voters[msg.sender].hasVoted, "the caller has already voted");

        voters[msg.sender].hasVoted = true;
        voters[msg.sender].votedCandidateId = _candidateId;

        candidates[_candidateId].voteCount += 1;

        emit VotedEvent(msg.sender, _candidateId);
    }

    function myVoteIs() public view returns (uint8) {
        return voters[msg.sender].votedCandidateId;
    }

    // ADMIN FUNCTIONS
    function registerElection(string memory _electionName, string memory _electionDescription)
    public onlyAdministrator onlyDuringElectionsRegistration {
        election.name = _electionName;
        election.description = _electionDescription;

        emit ElectionsRegisteredEvent();
    }

    function registerVoter(address _voterAddress)
    public onlyAdministrator onlyDuringVotersRegistration {
        require(!voters[_voterAddress].isRegistered, "the voter is already registered");

        voters[_voterAddress].isRegistered = true;
        voters[_voterAddress].isBurned = false;

        emit VoterRegisteredEvent(_voterAddress);
    }
    // later add no duplicated candidates
    function registerCandidate(string memory _candidateName, string memory _candidateMotto, string memory _photoUrl)
    public onlyAdministrator onlyDuringCandidatesRegistration {

        candidates.push(Candidate({
        name: _candidateName,
        motto: _candidateMotto,
        photoUrl: _photoUrl,
        voteCount: 0
        }));

        emit CandidateRegisteredEvent(candidates.length - 1);
    }

    function connectVerifier(address _verifierAddress) public onlyAdministrator onlyDuringVerifierGeneration {
        verifier = Verifier(_verifierAddress);

        emit VerifierConnectedEvent(_verifierAddress);
    }

    // WORKFLOW FUNCTIONS
    function startVotersRegistration() public onlyAdministrator onlyDuringElectionsRegistration{
        workflowStatus = WorkflowStatus.RegisteringVoters;

        emit WorkflowStatusChangeEvent(WorkflowStatus.RegisteringElections, workflowStatus);
    }
    // burn account that linked to the id and get the secret phrase session.
    function startBurnAndRetrieveSession() public onlyAdministrator onlyDuringVotersRegistration {
        workflowStatus = WorkflowStatus.BurnAndRetrieveSessionStarted;

        emit WorkflowStatusChangeEvent(WorkflowStatus.RegisteringVoters, workflowStatus);
    }

    function startCandidatesRegistration() public onlyAdministrator onlyDuringBaRSession{
        workflowStatus = WorkflowStatus.RegisteringCandidates;

        emit WorkflowStatusChangeEvent(WorkflowStatus.BurnAndRetrieveSessionStarted, workflowStatus);
    }

    function startVerifierGeneration() public onlyAdministrator onlyDuringCandidatesRegistration{
        workflowStatus = WorkflowStatus.GeneratingVerifier;

        emit WorkflowStatusChangeEvent(WorkflowStatus.RegisteringCandidates, workflowStatus);
    }

    function startVerificationSession() public onlyAdministrator onlyDuringVerifierGeneration{
        require(!(address(verifier) == address(0)), "the verifier should be connected firstly");
        workflowStatus = WorkflowStatus.VerifyingAccounts;

        emit WorkflowStatusChangeEvent(WorkflowStatus.GeneratingVerifier, workflowStatus);
    }

    function startVotingSession() public onlyAdministrator onlyDuringVerificationSession {
        workflowStatus = WorkflowStatus.VotingSessionStarted;

        emit WorkflowStatusChangeEvent(WorkflowStatus.VerifyingAccounts, workflowStatus);
    }

    function endVotingSession() public onlyAdministrator onlyDuringVotingSession {
        workflowStatus = WorkflowStatus.VotingSessionEnded;

        emit WorkflowStatusChangeEvent(WorkflowStatus.VotingSessionStarted, workflowStatus);
    }

    function tallyVotes() onlyAdministrator public {
        require(workflowStatus == WorkflowStatus.VotingSessionEnded,
            "this function can be called only after the voting session has ended");

        uint winningVoteCount = 0;
        uint winningCandidateIndex = 0;

        for (uint8 i = 0; i < candidates.length; i++) {
            if (candidates[i].voteCount > winningVoteCount) {
                winningVoteCount = candidates[i].voteCount;
                winningCandidateIndex = i;
            }
        }

        winningCandidate = candidates[winningCandidateIndex];
        workflowStatus = WorkflowStatus.VotesTallied;

        emit VotesTalliedEvent();
        emit WorkflowStatusChangeEvent(WorkflowStatus.VotingSessionEnded, workflowStatus);
    }

    // GETTERS
    function getCandidate(uint8 _candidateId) public view onlyDuringVotingSession returns (string memory, string memory, string memory) {
        return (candidates[_candidateId].name, candidates[_candidateId].motto, candidates[_candidateId].photoUrl);
    }

    function getHashes1() public view onlyDuringVerifierGeneration returns (uint128[] memory) {
        return hashesOfSecrets1;
    }

    function getHashes2() public view onlyDuringVerifierGeneration returns (uint128[] memory) {
        return hashesOfSecrets2;
    }

    function getWinningCandidate() public view onlyAfterVotesTallied returns (Candidate memory) {
        return winningCandidate;
    }

    function getCandidateNumber() public view onlyDuringVotingSession returns (uint256) {
        return candidates.length;
    }
}