const PrivateVoting = artifacts.require("PrivateVoting");

module.exports = function (deployer) {
    deployer.deploy(PrivateVoting);
};
